from odoo import api, fields, models
from odoo.exceptions import AccessError, UserError


class FfCollectionDeposit(models.Model):
    """A hand-over of collected money to the office."""
    _name = 'ff.collection.deposit'
    _description = 'Collection Deposit'
    _inherit = ['mail.thread', 'mail.activity.mixin']
    _order = 'submitted_at desc, id desc'

    name = fields.Char(default=lambda self: self.env._('New'), copy=False)
    employee_id = fields.Many2one('hr.employee', required=True, index=True, ondelete='cascade')
    team_id = fields.Many2one(related='employee_id.ff_team_id', store=True)
    department_id = fields.Many2one(related='employee_id.department_id', store=True)
    collection_ids = fields.One2many('ff.collection', 'deposit_id', string='Collections')
    amount = fields.Monetary(compute='_compute_amount', store=True)
    collection_count = fields.Integer(compute='_compute_amount', store=True)
    company_id = fields.Many2one(related='employee_id.company_id', store=True)
    currency_id = fields.Many2one(related='company_id.currency_id')
    submitted_at = fields.Datetime(default=fields.Datetime.now, required=True)
    received_at = fields.Datetime(readonly=True, copy=False)
    received_by_id = fields.Many2one('res.users', string='Received by', readonly=True, copy=False)
    reference = fields.Char(help='Bank slip number, receipt number...')
    note = fields.Text()
    state = fields.Selection([
        ('submitted', 'Submitted'),
        ('received', 'Received'),
        ('rejected', 'Rejected'),
    ], default='submitted', required=True, index=True, tracking=True)
    client_uuid = fields.Char(index=True, copy=False)

    _client_uuid_uniq = models.Constraint('UNIQUE(client_uuid)', 'This deposit was already received.')

    @api.depends('collection_ids.amount')
    def _compute_amount(self):
        for deposit in self:
            deposit.amount = sum(deposit.collection_ids.mapped('amount'))
            deposit.collection_count = len(deposit.collection_ids)

    @api.model_create_multi
    def create(self, vals_list):
        for vals in vals_list:
            if not vals.get('name') or vals['name'] == self.env._('New'):
                vals['name'] = self.env['ir.sequence'].sudo().next_by_code('ff.collection.deposit') or '/'
        return super().create(vals_list)

    @api.model
    def ff_submit_from_app(self, employee, data):
        """Employee hands over the selected collections (all pending ones by default)."""
        Deposit = self.sudo()
        uuid = data.get('uuid') or False
        if uuid:
            existing = Deposit.search([('client_uuid', '=', uuid)], limit=1)
            if existing:
                return existing
        Collection = self.env['ff.collection']
        pending = Collection._ff_pending(employee)
        ids = [int(i) for i in (data.get('collection_ids') or []) if str(i).isdigit()]
        collections = pending.filtered(lambda c: c.id in ids) if ids else pending
        if not collections:
            raise UserError(self.env._('There is nothing to submit.'))
        deposit = Deposit.create({
            'employee_id': employee.id,
            'reference': (data.get('reference') or '').strip() or False,
            'note': (data.get('note') or '').strip() or False,
            'client_uuid': uuid,
        })
        collections.write({'deposit_id': deposit.id, 'state': 'submitted'})
        manager_user = employee.parent_id.user_id
        if manager_user:
            deposit.activity_schedule('mail.mail_activity_data_todo', user_id=manager_user.id,
                                      summary=self.env._('Collect the money handed over'))
        return deposit

    def _ff_check_approver(self):
        user = self.env.user
        if user.has_group('ff_base.group_ff_admin'):
            return
        approver = user.employee_id
        for deposit in self:
            if not approver or not approver._ff_is_manager_of(deposit.employee_id):
                raise AccessError(self.env._('This deposit is outside your data access.'))

    def _ff_set_state(self, received, user_id=False):
        for deposit in self.sudo():
            if deposit.state != 'submitted':
                raise UserError(self.env._('Only submitted deposits can be decided.'))
            deposit.write({
                'state': 'received' if received else 'rejected',
                'received_at': fields.Datetime.now() if received else False,
                'received_by_id': user_id or False,
            })
            deposit.collection_ids.write({'state': 'received' if received else 'collected'})
            if not received:
                deposit.collection_ids.write({'deposit_id': False})
            deposit.activity_ids.unlink()

    def action_receive(self):
        self._ff_check_approver()
        self._ff_set_state(True, self.env.uid)

    def action_reject(self):
        self._ff_check_approver()
        self._ff_set_state(False, self.env.uid)

    def _ff_decide_as(self, employee, received):
        """Receive or reject from the mobile app on behalf of ``employee``."""
        self.ensure_one()
        if not employee._ff_is_manager_of(self.sudo().employee_id):
            raise AccessError(self.env._('This deposit is outside your data access.'))
        self._ff_set_state(received, employee.user_id.id)
