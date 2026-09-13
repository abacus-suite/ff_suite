"""Goods coming back from an outlet: unsold returns, and damaged or expired stock."""
from odoo import api, fields, models
from odoo.exceptions import UserError

from odoo.addons.ff_app_reports.models.ff_app_report import DATE, MONEY, NUMBER, STATUS, col
from odoo.addons.ff_base.tools import parse_client_dt

REASONS = [
    ('damaged', 'Damaged'),
    ('expired', 'Expired'),
    ('near_expiry', 'Near expiry'),
    ('wrong_item', 'Wrong item supplied'),
    ('unsold', 'Unsold / slow moving'),
    ('other', 'Other'),
]
STATES = [
    ('submitted', 'Waiting Approval'),
    ('approved', 'Approved'),
    ('rejected', 'Rejected'),
    ('credited', 'Credited'),
]


class FfReturn(models.Model):
    _name = 'ff.return'
    _description = 'Field Return'
    _inherit = ['mail.thread', 'mail.activity.mixin']
    _order = 'date desc, id desc'

    name = fields.Char(default=lambda self: self.env._('New'), copy=False, readonly=True)
    employee_id = fields.Many2one('hr.employee', string='Reported By', required=True, index=True,
                                  ondelete='restrict', tracking=True)
    team_id = fields.Many2one(related='employee_id.ff_team_id', store=True)
    department_id = fields.Many2one(related='employee_id.department_id', store=True)
    partner_id = fields.Many2one('res.partner', string='Outlet', required=True, index=True, tracking=True)
    visit_id = fields.Many2one('ff.visit', string='Visit', ondelete='set null')
    date = fields.Datetime(required=True, default=fields.Datetime.now, index=True)
    reason = fields.Selection(REASONS, required=True, default='damaged', tracking=True)
    note = fields.Text()
    line_ids = fields.One2many('ff.return.line', 'return_id', string='Products', copy=True)
    company_id = fields.Many2one(related='employee_id.company_id', store=True)
    currency_id = fields.Many2one(related='company_id.currency_id')
    amount_total = fields.Monetary(compute='_compute_totals', store=True, string='Value')
    quantity_total = fields.Float(compute='_compute_totals', store=True, string='Units')
    state = fields.Selection(STATES, default='submitted', required=True, index=True, tracking=True)
    approver_id = fields.Many2one('res.users', readonly=True, copy=False)
    decided_at = fields.Datetime(readonly=True, copy=False)
    credit_note_id = fields.Many2one('account.move', string='Credit Note', readonly=True, copy=False)
    photo_count = fields.Integer(compute='_compute_photo_count')
    latitude = fields.Float(digits=(10, 7))
    longitude = fields.Float(digits=(10, 7))

    @api.depends('line_ids.quantity', 'line_ids.price_unit')
    def _compute_totals(self):
        for record in self:
            record.quantity_total = sum(record.line_ids.mapped('quantity'))
            record.amount_total = sum(line.quantity * line.price_unit for line in record.line_ids)

    def _compute_photo_count(self):
        counts = dict(self.env['ir.attachment'].sudo()._read_group(
            [('res_model', '=', self._name), ('res_id', 'in', self.ids)], ['res_id'], ['__count']))
        for record in self:
            record.photo_count = counts.get(record.id, 0)

    @api.model_create_multi
    def create(self, vals_list):
        for vals in vals_list:
            if vals.get('name', self.env._('New')) == self.env._('New'):
                vals['name'] = self.env['ir.sequence'].next_by_code('ff.return') or self.env._('New')
        records = super().create(vals_list)
        for record in records:
            record._ff_tell_manager()
        return records

    # ------------------------------------------------------------------
    # Telling people
    # ------------------------------------------------------------------
    def _ff_push(self, title, body, employee=None, user=None):
        if 'ff.notification' in self.env:
            self.env['ff.notification'].sudo().ff_push(title, body, employee=employee, user=user, record=self)

    def _ff_tell_manager(self):
        manager = self.employee_id.parent_id
        body = self.env._('%(who)s reported %(reason)s goods at %(outlet)s (%(value)s).',
                          who=self.employee_id.name, reason=dict(REASONS)[self.reason].lower(),
                          outlet=self.partner_id.display_name,
                          value='%s %.2f' % (self.currency_id.symbol or '', self.amount_total))
        if manager:
            self._ff_push(self.env._('Return to approve'), body, employee=manager)
            if manager.user_id:
                self.sudo().activity_schedule('mail.mail_activity_data_todo', user_id=manager.user_id.id,
                                              summary=self.env._('Approve return %s', self.name))

    # ------------------------------------------------------------------
    # Decisions
    # ------------------------------------------------------------------
    def _ff_decide(self, approve, user):
        for record in self.sudo():
            if record.state != 'submitted':
                raise UserError(self.env._('%s has already been decided.', record.name))
            record.write({'state': 'approved' if approve else 'rejected', 'approver_id': user.id,
                          'decided_at': fields.Datetime.now()})
            record.activity_ids.unlink()
            record._ff_push(self.env._('Return approved') if approve else self.env._('Return rejected'),
                            '%s · %s' % (record.name, record.partner_id.display_name), employee=record.employee_id)

    def action_approve(self):
        self._ff_decide(True, self.env.user)

    def action_reject(self):
        self._ff_decide(False, self.env.user)

    def ff_decide_as(self, employee, approve):
        self.ensure_one()
        if self.employee_id not in employee._ff_subordinates():
            raise UserError(self.env._('This return is not yours to decide.'))
        self._ff_decide(approve, employee.user_id or self.env.user)
        return self

    def action_create_credit_note(self):
        """A draft customer credit note for the approved goods, for accounts to check and post."""
        self.ensure_one()
        if self.state != 'approved':
            raise UserError(self.env._('Approve the return before crediting it.'))
        if self.credit_note_id:
            return self.action_open_credit_note()
        lines = [(0, 0, {
            'product_id': line.product_id.id,
            'quantity': line.quantity,
            'price_unit': line.price_unit,
            'name': '%s - %s' % (line.product_id.display_name, dict(REASONS)[self.reason]),
        }) for line in self.line_ids if line.quantity]
        if not lines:
            raise UserError(self.env._('There is nothing to credit.'))
        move = self.env['account.move'].sudo().create({
            'move_type': 'out_refund',
            'partner_id': self.partner_id.commercial_partner_id.id,
            'company_id': self.company_id.id,
            'invoice_origin': self.name,
            'ref': '%s (%s)' % (self.name, dict(REASONS)[self.reason]),
            'invoice_line_ids': lines,
        })
        self.sudo().write({'credit_note_id': move.id, 'state': 'credited'})
        return self.action_open_credit_note()

    def action_open_credit_note(self):
        self.ensure_one()
        return {'type': 'ir.actions.act_window', 'res_model': 'account.move', 'res_id': self.credit_note_id.id,
                'view_mode': 'form', 'target': 'current'}

    # ------------------------------------------------------------------
    # From the app
    # ------------------------------------------------------------------
    @api.model
    def ff_create_from_app(self, employee, partner, data):
        Product = self.env['product.product'].sudo()
        lines = []
        for line in data.get('lines') or []:
            try:
                quantity = float(line.get('qty') or line.get('quantity') or 0)
            except (TypeError, ValueError):
                continue
            if quantity <= 0:
                continue
            product = Product.browse(int(line.get('product_id') or 0)).exists()
            if not product:
                raise UserError(self.env._('Product %s was not found.', line.get('product_id')))
            price = product.ff_field_price() if hasattr(product, 'ff_field_price') else product.lst_price
            lines.append((0, 0, {'product_id': product.id, 'quantity': quantity, 'price_unit': price,
                                 'batch': (line.get('batch') or '').strip() or False,
                                 'expiry_date': line.get('expiry_date') or False}))
        if not lines:
            raise UserError(self.env._('Add at least one product that is coming back.'))
        reason = data.get('reason') if data.get('reason') in dict(REASONS) else 'other'
        visit = self.env['ff.visit'].sudo().search([
            ('employee_id', '=', employee.id), ('partner_id', '=', partner.id), ('state', '=', 'ongoing')], limit=1)
        record = self.sudo().create({
            'employee_id': employee.id,
            'partner_id': partner.id,
            'visit_id': visit.id or False,
            'date': parse_client_dt(data.get('at')) or fields.Datetime.now(),
            'reason': reason,
            'note': (data.get('note') or '').strip() or False,
            'line_ids': lines,
            'latitude': float(data.get('lat') or 0.0),
            'longitude': float(data.get('lng') or 0.0),
        })
        photos = [p for p in (data.get('photos') or []) if isinstance(p, str) and p][:6]
        if photos:
            self.env['ir.attachment'].sudo().create([{
                'name': '%s_%d.jpg' % (record.name.replace('/', '_'), i + 1),
                'datas': photo.split(',', 1)[1] if ',' in photo[:80] else photo,
                'res_model': self._name, 'res_id': record.id, 'mimetype': 'image/jpeg',
            } for i, photo in enumerate(photos)])
        return record

    def ff_payload(self):
        self.ensure_one()
        return {
            'id': self.id,
            'name': self.name,
            'date': fields.Datetime.to_string(self.date),
            'customer': {'id': self.partner_id.id, 'name': self.partner_id.display_name},
            'employee': {'id': self.employee_id.id, 'name': self.employee_id.name},
            'reason': self.reason,
            'reason_label': dict(REASONS)[self.reason],
            'state': self.state,
            'state_label': dict(STATES)[self.state],
            'amount': round(self.amount_total, 2),
            'units': self.quantity_total,
            'currency': self.currency_id.name,
            'note': self.note or None,
            'photos': self.photo_count,
            'lines': [{'product': line.product_id.display_name, 'quantity': line.quantity,
                       'price': line.price_unit, 'batch': line.batch or None,
                       'expiry_date': fields.Date.to_string(line.expiry_date) if line.expiry_date else None}
                      for line in self.line_ids],
        }


class FfReturnLine(models.Model):
    _name = 'ff.return.line'
    _description = 'Field Return Line'

    return_id = fields.Many2one('ff.return', required=True, ondelete='cascade', index=True)
    product_id = fields.Many2one('product.product', required=True)
    quantity = fields.Float(default=1.0)
    price_unit = fields.Float(string='Unit Value')
    batch = fields.Char(string='Batch / Lot')
    expiry_date = fields.Date()
    currency_id = fields.Many2one(related='return_id.currency_id')
    subtotal = fields.Monetary(compute='_compute_subtotal', currency_field='currency_id')

    @api.depends('quantity', 'price_unit')
    def _compute_subtotal(self):
        for line in self:
            line.subtotal = line.quantity * line.price_unit


class FfAppReportReturns(models.AbstractModel):
    _inherit = 'ff.app.report'

    def _definitions(self):
        defs = super()._definitions()
        defs['returns'] = ('Returns & damaged', 'Goods coming back from outlets', 'assignment_return', 'ff.return', [
            col('date', 'Date', DATE), col('number', 'Number'), col('employee', 'Employee'),
            col('customer', 'Outlet'), col('reason', 'Reason'), col('units', 'Units', NUMBER, True),
            col('amount', 'Value', MONEY, True), col('status', 'Status', STATUS)], self._returns)
        return defs

    def _returns(self, employees, start, end):
        low, high = self._utc_bounds(start, end)
        records = self.env['ff.return'].sudo().search([
            ('employee_id', 'in', employees.ids), ('date', '>=', low), ('date', '<', high)], order='date desc')
        return [{
            'date': self._local(r.employee_id, r.date).date().isoformat(),
            'number': r.name, 'employee': r.employee_id.name, 'customer': r.partner_id.display_name,
            'reason': dict(REASONS)[r.reason], 'units': r.quantity_total,
            'amount': 0.0 if r.state == 'rejected' else r.amount_total, 'status': dict(STATES)[r.state],
        } for r in records]
