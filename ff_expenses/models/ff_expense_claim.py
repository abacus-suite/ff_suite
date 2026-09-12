from odoo import api, fields, models
from odoo.exceptions import AccessError, UserError, ValidationError

MAX_RECEIPTS = 5


def _strip_data_url(image):
    if isinstance(image, str) and image.startswith('data:') and ',' in image:
        return image.split(',', 1)[1]
    return image


class FfExpenseClaim(models.Model):
    _name = 'ff.expense.claim'
    _description = 'Field Expense Claim'
    _inherit = ['mail.thread', 'mail.activity.mixin']
    _order = 'date desc, id desc'

    name = fields.Char(compute='_compute_name', store=True)
    employee_id = fields.Many2one('hr.employee', required=True, index=True, ondelete='cascade',
                                  default=lambda self: self.env.user.employee_id)
    team_id = fields.Many2one(related='employee_id.ff_team_id', store=True)
    department_id = fields.Many2one(related='employee_id.department_id', store=True)
    date = fields.Date(required=True, index=True, default=fields.Date.context_today, tracking=True)
    category_id = fields.Many2one('ff.expense.category', string='Expense Type', required=True, tracking=True)
    amount = fields.Monetary(required=True, tracking=True)
    company_id = fields.Many2one(related='employee_id.company_id', store=True)
    currency_id = fields.Many2one(related='company_id.currency_id')
    note = fields.Text()
    partner_id = fields.Many2one('res.partner', string='Contact')
    visit_id = fields.Many2one('ff.visit', string='Visit', ondelete='set null')
    latitude = fields.Float(digits=(10, 7))
    longitude = fields.Float(digits=(10, 7))
    receipt_count = fields.Integer(compute='_compute_receipt_count')
    state = fields.Selection([
        ('draft', 'Draft'),
        ('submitted', 'To Approve'),
        ('approved', 'Approved'),
        ('rejected', 'Rejected'),
    ], default='draft', required=True, index=True, tracking=True)
    approver_id = fields.Many2one('res.users', readonly=True, copy=False)
    decided_at = fields.Datetime(readonly=True, copy=False)
    client_uuid = fields.Char(index=True, copy=False)

    _client_uuid_uniq = models.Constraint('UNIQUE(client_uuid)', 'This claim was already received.')

    @api.depends('category_id', 'date', 'employee_id')
    def _compute_name(self):
        for claim in self:
            claim.name = '%s - %s' % (claim.category_id.name or '', claim.date or '')

    def _compute_receipt_count(self):
        counts = dict(self.env['ir.attachment'].sudo()._read_group(
            [('res_model', '=', self._name), ('res_id', 'in', self.ids)], ['res_id'], ['__count']))
        for claim in self:
            claim.receipt_count = counts.get(claim.id, 0)

    @api.constrains('amount', 'category_id')
    def _check_amount(self):
        for claim in self:
            if claim.amount <= 0:
                raise ValidationError(self.env._('The amount must be more than zero.'))
            limit = claim.category_id.max_amount
            if limit and claim.amount > limit:
                raise ValidationError(self.env._(
                    'The maximum for "%(type)s" is %(limit)s.', type=claim.category_id.name, limit=limit))

    # ------------------------------------------------------------------
    # Mobile app
    # ------------------------------------------------------------------
    @api.model
    def ff_create_from_app(self, employee, data):
        """Create (and submit) a claim sent from the app. Idempotent on ``uuid``."""
        Claim = self.sudo()
        uuid = data.get('uuid') or False
        if uuid:
            existing = Claim.search([('client_uuid', '=', uuid)], limit=1)
            if existing:
                return existing
        categories = self.env['ff.expense.category'].ff_for_employee(employee)
        category = categories.filtered(lambda c: str(c.id) == str(data.get('category_id')))
        if not category:
            raise UserError(self.env._('Choose an expense type you have access to.'))
        try:
            amount = float(data.get('amount'))
        except (TypeError, ValueError):
            raise UserError(self.env._('Enter the amount.'))
        receipts = [r for r in (data.get('receipts') or []) if isinstance(r, str) and r][:MAX_RECEIPTS]
        if category.requires_receipt and not receipts:
            raise UserError(self.env._('A receipt photo is required for "%s".', category.name))

        partner = self.env['res.partner'].sudo().browse(int(data['partner_id'])).exists() \
            if str(data.get('partner_id') or '').isdigit() else self.env['res.partner']
        if category.requires_client and not partner:
            raise UserError(self.env._('Choose the contact this expense belongs to.'))
        visit = self.env['ff.visit'].sudo().browse(int(data['visit_id'])).exists() \
            if str(data.get('visit_id') or '').isdigit() else self.env['ff.visit']
        if visit and visit.employee_id != employee:
            raise AccessError(self.env._('This visit is not yours.'))

        claim = Claim.create({
            'employee_id': employee.id,
            'category_id': category.id,
            'date': fields.Date.to_date(data.get('date')) or employee._ff_today(),
            'amount': amount,
            'note': (data.get('note') or '').strip() or False,
            'partner_id': partner.id or (visit.partner_id.id if visit else False),
            'visit_id': visit.id or False,
            'latitude': data.get('lat') or 0.0,
            'longitude': data.get('lng') or 0.0,
            'client_uuid': uuid,
        })
        if receipts:
            self.env['ir.attachment'].sudo().create([{
                'name': 'receipt_%s_%s.jpg' % (claim.id, index + 1),
                'datas': _strip_data_url(receipt),
                'res_model': self._name,
                'res_id': claim.id,
                'mimetype': 'image/jpeg',
            } for index, receipt in enumerate(receipts)])
        claim.action_submit()
        return claim

    # ------------------------------------------------------------------
    # Workflow
    # ------------------------------------------------------------------
    def action_submit(self):
        for claim in self.filtered(lambda c: c.state == 'draft'):
            claim.state = 'submitted'
            manager_user = claim.employee_id.parent_id.user_id
            if manager_user:
                claim.sudo().activity_schedule('mail.mail_activity_data_todo', user_id=manager_user.id,
                                               summary=self.env._('Approve expense claim'))

    def _ff_check_approver(self):
        user = self.env.user
        if user.has_group('ff_base.group_ff_admin'):
            return
        approver = user.employee_id
        for claim in self:
            if not approver or not approver._ff_is_manager_of(claim.employee_id):
                raise AccessError(self.env._('This claim is outside your data access.'))

    def _ff_set_decision(self, approve, approver_user=False):
        for claim in self.sudo():
            if claim.state != 'submitted':
                raise UserError(self.env._('Only submitted claims can be decided.'))
            claim.write({'state': 'approved' if approve else 'rejected',
                         'approver_id': approver_user or False, 'decided_at': fields.Datetime.now()})
            claim.activity_ids.unlink()

    def action_approve(self):
        self._ff_check_approver()
        self._ff_set_decision(True, self.env.uid)

    def action_reject(self):
        self._ff_check_approver()
        self._ff_set_decision(False, self.env.uid)

    def action_reset_draft(self):
        self._ff_check_approver()
        self.sudo().filtered(lambda c: c.state == 'rejected').write({'state': 'draft'})

    def _ff_decide_as(self, employee, approve):
        """Approve or reject from the mobile app on behalf of ``employee``."""
        self.ensure_one()
        if not employee._ff_is_manager_of(self.sudo().employee_id):
            raise AccessError(self.env._('This claim is outside your data access.'))
        self._ff_set_decision(approve, employee.user_id.id)
