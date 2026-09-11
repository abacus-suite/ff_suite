from datetime import timedelta

from odoo import api, fields, models
from odoo.exceptions import AccessError, UserError, ValidationError

REASONS = [
    ('battery', 'Phone battery died'),
    ('network', 'No network'),
    ('forgot', 'Forgot to punch'),
    ('field_duty', 'Field duty / outstation'),
    ('other', 'Other'),
]


class FfRegularisation(models.Model):
    _name = 'ff.regularisation'
    _description = 'Attendance Regularisation Request'
    _inherit = ['mail.thread', 'mail.activity.mixin']
    _order = 'date desc, id desc'

    employee_id = fields.Many2one(
        'hr.employee', required=True, index=True, tracking=True,
        default=lambda self: self.env.user.employee_id)
    manager_id = fields.Many2one(related='employee_id.parent_id', string='Manager')
    date = fields.Date(required=True, default=fields.Date.context_today, tracking=True)
    check_in = fields.Datetime(required=True, tracking=True)
    check_out = fields.Datetime(required=True, tracking=True)
    reason = fields.Selection(REASONS, required=True, default='forgot')
    note = fields.Text()
    state = fields.Selection([
        ('draft', 'Draft'),
        ('submitted', 'To Approve'),
        ('approved', 'Approved'),
        ('rejected', 'Rejected'),
    ], default='draft', required=True, tracking=True)
    approver_id = fields.Many2one('res.users', readonly=True, copy=False)
    decided_at = fields.Datetime(readonly=True, copy=False)
    attendance_id = fields.Many2one('hr.attendance', readonly=True, copy=False)

    @api.depends('employee_id', 'date')
    def _compute_display_name(self):
        for rec in self:
            rec.display_name = '%s - %s' % (rec.employee_id.name or '', rec.date or '')

    @api.constrains('check_in', 'check_out')
    def _check_times(self):
        for rec in self:
            if rec.check_out <= rec.check_in:
                raise ValidationError(self.env._('Punch-out must be after punch-in.'))
            if rec.check_out - rec.check_in > timedelta(hours=24):
                raise ValidationError(self.env._('A regularised day cannot exceed 24 hours.'))

    def action_submit(self):
        for rec in self.filtered(lambda r: r.state == 'draft'):
            rec.state = 'submitted'
            manager_user = rec.employee_id.parent_id.user_id
            if manager_user:
                rec.sudo().activity_schedule(
                    'mail.mail_activity_data_todo', user_id=manager_user.id,
                    summary=self.env._('Approve attendance regularisation'))

    def _ff_check_approver(self):
        user = self.env.user
        if user.has_group('ff_base.group_ff_admin'):
            return
        approver = user.employee_id
        for rec in self:
            if not approver or not approver._ff_is_manager_of(rec.employee_id):
                raise AccessError(self.env._("Only the employee's manager can decide on this request."))

    def action_approve(self):
        self._ff_check_approver()
        for rec in self:
            if rec.state != 'submitted':
                raise UserError(self.env._('Only submitted requests can be approved.'))
            rec._ff_apply()
            rec.write({'state': 'approved', 'approver_id': self.env.uid, 'decided_at': fields.Datetime.now()})
            rec.sudo().activity_ids.unlink()

    def action_reject(self):
        self._ff_check_approver()
        for rec in self:
            if rec.state != 'submitted':
                raise UserError(self.env._('Only submitted requests can be rejected.'))
            rec.write({'state': 'rejected', 'approver_id': self.env.uid, 'decided_at': fields.Datetime.now()})
            rec.sudo().activity_ids.unlink()

    def _ff_decide_as(self, employee, approve):
        """Approve or reject from the mobile app on behalf of ``employee``."""
        self.ensure_one()
        rec = self.sudo()
        if not employee._ff_is_manager_of(rec.employee_id):
            raise AccessError(self.env._('This request is outside your data access.'))
        if rec.state != 'submitted':
            raise UserError(self.env._('Only submitted requests can be decided.'))
        if approve:
            rec._ff_apply()
        rec.write({
            'state': 'approved' if approve else 'rejected',
            'approver_id': employee.user_id.id or False,
            'decided_at': fields.Datetime.now(),
        })
        rec.message_post(body=self.env._('%(decision)s in the mobile app by %(name)s.',
                                         decision=self.env._('Approved') if approve else self.env._('Rejected'),
                                         name=employee.name))
        rec.activity_ids.unlink()
        return rec

    def action_reset_draft(self):
        self.filtered(lambda r: r.state == 'rejected').write({'state': 'draft'})

    def _ff_apply(self):
        self.ensure_one()
        Attendance = self.env['hr.attendance'].sudo()
        overlapping = Attendance.search([
            ('employee_id', '=', self.employee_id.id),
            ('check_in', '<', self.check_out),
            '|', ('check_out', '=', False), ('check_out', '>', self.check_in),
        ])
        if len(overlapping) > 1:
            raise UserError(self.env._(
                'Several attendances overlap this period. Please correct them manually in Attendances.'))
        vals = {'check_in': self.check_in, 'check_out': self.check_out, 'ff_source': 'regularisation'}
        if overlapping:
            overlapping.write(vals)
            self.attendance_id = overlapping
        else:
            self.attendance_id = Attendance.create(dict(vals, employee_id=self.employee_id.id))
