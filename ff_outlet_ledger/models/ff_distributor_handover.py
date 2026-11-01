"""Outlet money handed over to its distributor.

A salesperson collects from outlets and keeps the cash until it is given to the
distributor those outlets buy from. One handover covers every outlet payment
for one distributor that was given in one go. The office confirms it, which
confirms the payments inside it and so marks the outlet invoices as paid.
"""
from datetime import datetime, timezone

from odoo import api, fields, models
from odoo.exceptions import AccessError, UserError


class FfDistributorHandover(models.Model):
    _name = 'ff.distributor.handover'
    _description = 'Handover to Distributor'
    _inherit = ['mail.thread']
    _order = 'date desc, id desc'

    name = fields.Char(default=lambda self: self.env._('New'), copy=False, readonly=True)
    employee_id = fields.Many2one('hr.employee', string='Handed by', required=True, index=True, ondelete='cascade')
    distributor_id = fields.Many2one('res.partner', string='Handed to', required=True, index=True,
                                     domain=[('ff_is_distributor', '=', True)], tracking=True)
    date = fields.Datetime(required=True, default=fields.Datetime.now, index=True)
    payment_ids = fields.One2many('ff.outlet.payment', 'handover_id', string='Outlet Payments',
                                  help='Older handovers, which gave whole payments.')
    line_ids = fields.One2many('ff.distributor.handover.line', 'handover_id', string='Given From')
    received_by = fields.Char(string='Received by', help='The person at the distributor who took the money.')
    count = fields.Integer(compute='_compute_amount', store=True)
    company_id = fields.Many2one('res.company', required=True, default=lambda self: self.env.company)
    currency_id = fields.Many2one(related='company_id.currency_id')
    amount = fields.Monetary(compute='_compute_amount', store=True, tracking=True)
    mode_id = fields.Many2one('ff.collection.mode', string='Mode')
    reference = fields.Char(string='Receipt / Reference')
    note = fields.Text()
    client_uuid = fields.Char(index=True, copy=False)
    state = fields.Selection([
        ('handed', 'Handed Over'), ('confirmed', 'Confirmed'), ('rejected', 'Rejected'),
    ], default='handed', required=True, index=True, tracking=True)
    decided_by_id = fields.Many2one('res.users', readonly=True, copy=False)
    decided_at = fields.Datetime(readonly=True, copy=False)

    @api.depends('payment_ids.amount', 'line_ids.amount')
    def _compute_amount(self):
        for record in self:
            if record.line_ids:
                record.amount = sum(record.line_ids.mapped('amount'))
                record.count = len(record.line_ids)
            else:
                record.amount = sum(record.payment_ids.mapped('amount'))
                record.count = len(record.payment_ids)

    @api.model_create_multi
    def create(self, vals_list):
        for vals in vals_list:
            if vals.get('name', self.env._('New')) == self.env._('New'):
                vals['name'] = self.env['ir.sequence'].sudo().next_by_code('ff.distributor.handover') or '/'
        return super().create(vals_list)

    # ------------------------------------------------------------------
    # From the app
    # ------------------------------------------------------------------
    @api.model
    def ff_pending(self, employee):
        """Outlet payments still with the employee, grouped by the distributor they belong to."""
        payments = self.env['ff.outlet.payment'].sudo().search([
            ('employee_id', '=', employee.id), ('state', '!=', 'rejected'), ('amount_held', '>', 0.004),
        ], order='date asc')
        groups = {}
        for payment in payments:
            groups[payment.distributor_id] = groups.get(payment.distributor_id, payments.browse()) | payment
        return groups

    @api.model
    def ff_submit_from_app(self, employee, data):
        uuid = data.get('uuid') or False
        if uuid:
            seen = self.sudo().search([('client_uuid', '=', uuid)], limit=1)
            if seen:
                return seen
        distributor = self.env['res.partner'].sudo().browse(int(data.get('distributor_id') or 0)).exists()
        if not distributor:
            raise UserError(self.env._('Choose the distributor the money is being given to.'))
        pending = self.ff_pending(employee).get(distributor)
        if not pending:
            raise UserError(self.env._('You hold no money for %s.', distributor.name))
        # What is given, outlet payment by outlet payment: the whole of it, or only part.
        wanted = {}
        for item in data.get('items') or []:
            try:
                wanted[int(item.get('payment_id'))] = float(item.get('amount') or 0)
            except (TypeError, ValueError):
                continue
        if not wanted:
            for pid in data.get('payment_ids') or []:
                if str(pid).isdigit():
                    wanted[int(pid)] = None
        if not wanted:
            wanted = {p.id: None for p in pending}
        lines = []
        for payment in pending:
            if payment.id not in wanted:
                continue
            amount = payment.amount_held if wanted[payment.id] is None else wanted[payment.id]
            if amount <= 0:
                continue
            if amount - payment.amount_held > 0.005:
                raise UserError(self.env._(
                    'Only %(held)s of %(name)s is still with you.',
                    held=payment.currency_id.format(payment.amount_held), name=payment.display_name))
            lines.append((0, 0, {'payment_id': payment.id, 'amount': amount}))
        if not lines:
            raise UserError(self.env._('Give an amount for at least one collection.'))
        mode = self.env['ff.collection.mode'].sudo().browse(int(data.get('mode_id') or 0)).exists()
        when = fields.Datetime.now()
        raw = (data.get('date') or '').strip() if isinstance(data.get('date'), str) else ''
        if raw:
            try:
                parsed = datetime.fromisoformat(raw.replace('Z', '+00:00'))
                if parsed.tzinfo:
                    parsed = parsed.astimezone(timezone.utc).replace(tzinfo=None)
                when = parsed
            except ValueError:
                pass
        handover = self.sudo().create({
            'employee_id': employee.id,
            'distributor_id': distributor.id,
            'company_id': employee.company_id.id,
            'date': when,
            'received_by': (data.get('received_by') or '').strip() or False,
            'mode_id': mode.id or False,
            'reference': (data.get('reference') or '').strip() or False,
            'note': (data.get('note') or '').strip() or False,
            'client_uuid': uuid,
            'line_ids': lines,
        })
        return handover

    def _ff_outlets(self):
        """The outlets whose money is in this handover."""
        self.ensure_one()
        return (self.line_ids.payment_id | self.payment_ids).partner_id

    def ff_app_payload(self, lines=False):
        self.ensure_one()
        data = {
            'id': self.id, 'name': self.name, 'date': self.date.isoformat() if self.date else None,
            'distributor': {'id': self.distributor_id.id, 'name': self.distributor_id.name},
            'amount': self.amount, 'count': self.count, 'state': self.state,
            'reference': self.reference or None, 'mode': self.mode_id.name or None,
            'currency': self.currency_id.name,
            'received_by': self.received_by or None, 'note': self.note or None,
        }
        if lines:
            if self.line_ids:
                data['payments'] = [dict(l.payment_id.ff_app_payload(), amount=l.amount) for l in self.line_ids]
            else:
                data['payments'] = [p.ff_app_payload() for p in self.payment_ids]
        return data

    # ------------------------------------------------------------------
    # Office side
    # ------------------------------------------------------------------
    def _ff_check_verifier(self):
        if self.env.context.get('ff_skip_verifier'):
            return
        user = self.env.user
        if not (user.has_group('ff_base.group_ff_manager') or user.has_group('account.group_account_user')):
            raise AccessError(self.env._('Only a manager or accounting can confirm a handover.'))

    def ff_decide_as(self, employee, approve):
        """A manager confirms or rejects a handover from the app: only for somebody in their team."""
        for handover in self:
            if handover.employee_id not in employee._ff_subordinates():
                raise AccessError(self.env._('This handover is not from your team.'))
        records = self.with_context(ff_skip_verifier=True)
        return records.action_confirm() if approve else records.action_reject()

    def action_confirm(self):
        self._ff_check_verifier()
        for handover in self:
            if handover.state != 'handed':
                raise UserError(self.env._('%s has already been dealt with.', handover.name))
            handover.payment_ids.filtered(lambda p: p.state == 'given').sudo().write({
                'state': 'confirmed', 'confirmed_by_id': self.env.uid, 'confirmed_at': fields.Datetime.now()})
        self.sudo().write({'state': 'confirmed', 'decided_by_id': self.env.uid, 'decided_at': fields.Datetime.now()})
        # A part-given payment is confirmed once all of it is given and every part is confirmed.
        for payment in self.line_ids.payment_id.sudo():
            parts = payment.handover_line_ids.filtered(lambda l: l.handover_id.state != 'rejected')
            if payment.state == 'given' and payment.amount_held <= 0.004 and \
                    all(l.handover_id.state == 'confirmed' for l in parts):
                payment.write({'state': 'confirmed', 'confirmed_by_id': self.env.uid,
                               'confirmed_at': fields.Datetime.now()})

    def action_reject(self):
        self._ff_check_verifier()
        for handover in self:
            if handover.state != 'handed':
                raise UserError(self.env._('%s has already been dealt with.', handover.name))
            # The money is still with the salesperson: it goes back to be handed over again.
            handover.payment_ids.sudo().write({'handover_id': False})
            # Parts given by amount simply stop counting: that money is with the salesperson again.
        self.sudo().write({'state': 'rejected', 'decided_by_id': self.env.uid, 'decided_at': fields.Datetime.now()})


class FfDistributorHandoverLine(models.Model):
    """How much of one outlet payment went to the distributor in one handover."""
    _name = 'ff.distributor.handover.line'
    _description = 'Handover Line'
    _order = 'id'

    handover_id = fields.Many2one('ff.distributor.handover', required=True, index=True, ondelete='cascade')
    payment_id = fields.Many2one('ff.outlet.payment', required=True, index=True, ondelete='restrict')
    partner_id = fields.Many2one(related='payment_id.partner_id', store=True, string='Outlet')
    currency_id = fields.Many2one(related='handover_id.currency_id')
    amount = fields.Monetary(required=True)
    state = fields.Selection(related='handover_id.state', store=True)
    date = fields.Datetime(related='handover_id.date', store=True)

    @api.constrains('amount')
    def _check_amount(self):
        for line in self:
            if line.amount <= 0:
                raise UserError(self.env._('A part handed over must be more than zero.'))
