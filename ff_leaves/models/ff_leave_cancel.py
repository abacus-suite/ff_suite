"""Cancelling a leave that was already approved: the employee wants to work on a day he had leave for."""
from odoo import api, fields, models
from odoo.exceptions import AccessError, UserError


class FfLeaveCancel(models.Model):
    _name = 'ff.leave.cancel'
    _description = 'Approved Leave Cancellation'
    _inherit = ['mail.thread']
    _order = 'id desc'

    leave_id = fields.Many2one('hr.leave', required=True, ondelete='cascade', index=True)
    employee_id = fields.Many2one(related='leave_id.employee_id', store=True, index=True)
    levels = fields.Selection([('1', 'Manager'), ('2', 'Manager, then HR')], default='1', required=True)
    state = fields.Selection([
        ('manager', 'Waiting for the manager'), ('hr', 'Waiting for HR'),
        ('done', 'Cancelled'), ('rejected', 'Rejected'),
    ], default='manager', required=True, tracking=True, index=True)
    reason = fields.Char()
    manager_user_id = fields.Many2one('res.users', readonly=True)
    hr_user_id = fields.Many2one('res.users', readonly=True)
    decided_at = fields.Datetime(readonly=True)

    @api.depends('leave_id')
    def _compute_display_name(self):
        for rec in self:
            rec.display_name = 'Cancel %s' % (rec.leave_id.display_name or '')

    # ------------------------------------------------------------------ settings
    @api.model
    def _ff_needs_approval(self):
        return self.env['ir.config_parameter'].sudo().get_param('ff_leaves.cancel_needs_approval') in ('True', '1', 'true')

    @api.model
    def _ff_levels(self):
        return '2' if self.env['ir.config_parameter'].sudo().get_param('ff_leaves.cancel_levels') == '2' else '1'

    # ------------------------------------------------------------------ the employee
    @api.model
    def ff_auto_cancel_for_checkin(self, employee, leave, reason='Check-in attempted'):
        """Auto-cancel a leave (approved or waiting for approval) when the employee checks in."""
        leave = leave.sudo()
        if leave.employee_id != employee:
            raise AccessError(self.env._('This leave is not yours.'))
        if leave.state in ('refuse', 'cancel'):
            rec = self.sudo().search([('leave_id', '=', leave.id)], limit=1)
            return rec or self.browse()

        today = employee._ff_today()
        # 1. Skip any pending approval chain steps
        if 'approval_line_ids' in leave._fields:
            leave.approval_line_ids.filtered(lambda l: l.state == 'pending').write({'state': 'skipped'})

        # 2. Cancel/refuse the leave
        try:
            leave.with_context(ff_chain_finished=True).action_refuse()
        except Exception:
            try:
                leave.with_context(ff_chain_finished=True).write({'state': 'cancel'})
            except Exception:
                pass

        # 3. Post chatter message with the reason and notify manager
        managers = employee.parent_id
        if 'approval_line_ids' in leave._fields:
            approver_emps = leave.approval_line_ids.mapped('user_id.employee_id')
            managers |= approver_emps
        partner_ids = [m.user_id.partner_id.id for m in managers if m.user_id and m.user_id.partner_id]
        leave.message_post(
            body=self.env._('Auto-cancelled: %(name)s %(reason)s on %(date)s.',
                            name=employee.name, reason=(reason or 'started work').lower(), date=today),
            partner_ids=partner_ids,
        )

        # 4. Mark or create any cancel record as done
        rec = self.sudo().search([('leave_id', '=', leave.id)], limit=1)
        if not rec:
            rec = self.sudo().create({
                'leave_id': leave.id,
                'reason': reason or 'Started work',
                'state': 'done',
                'levels': '1',
                'decided_at': fields.Datetime.now(),
            })
        else:
            rec.write({'state': 'done', 'reason': reason or 'Started work', 'decided_at': fields.Datetime.now()})

        # 5. Send push notification to employee
        if 'ff.notification' in self.env and employee:
            self.env['ff.notification'].sudo().ff_push(
                title=self.env._('Leave Auto-Cancelled'),
                body=self.env._('Your leave of %(date)s was auto-cancelled because you %(reason)s.',
                                date=leave.request_date_from, reason=(reason or 'started work').lower()),
                kind='decision', employee=employee, record=leave)

        # 6. Notify manager
        if 'ff.notification' in self.env:
            for mgr in managers:
                self.env['ff.notification'].sudo().ff_push(
                    title=self.env._('Leave Auto-Cancelled: %(name)s', name=employee.name),
                    body=self.env._('%(name)s started work on %(date)s. Their leave application was auto-cancelled.',
                                    name=employee.name, date=today),
                    kind='warning',
                    employee=mgr,
                    record=leave)

        return rec

    @api.model
    def ff_request(self, employee, leave, reason=''):
        """The employee asks to cancel an approved leave. With no approval needed it is cancelled at once."""
        leave = leave.sudo()
        if leave.employee_id != employee:
            raise AccessError(self.env._('This leave is not yours.'))
        if leave.state != 'validate':
            raise UserError(self.env._('Only an approved leave can be cancelled this way.'))
        again = self.sudo().search([('leave_id', '=', leave.id), ('state', 'in', ('manager', 'hr'))], limit=1)
        if again:
            return again
        if not self._ff_needs_approval():
            rec = self.sudo().create({'leave_id': leave.id, 'reason': reason, 'state': 'done',
                                      'levels': '1', 'decided_at': fields.Datetime.now()})
            rec._ff_cancel_leave()
            return rec
        rec = self.sudo().create({'leave_id': leave.id, 'reason': reason, 'levels': self._ff_levels()})
        if not employee.sudo().parent_id:
            # Nobody to ask first: straight to the next step, or done.
            rec._ff_after_manager()
        else:
            rec._ff_notify_approver(employee.sudo().parent_id)
        return rec

    # ------------------------------------------------------------------ the approvers
    @api.model
    def ff_pending_for(self, leave, approver):
        """The cancellation of ``leave`` that is waiting for ``approver`` (an employee), if any."""
        for rec in self.sudo().search([('leave_id', '=', leave.id), ('state', 'in', ('manager', 'hr'))]):
            if rec._ff_awaits(approver):
                return rec
        return self.browse()

    def _ff_awaits(self, approver):
        self.ensure_one()
        user = approver.sudo().user_id
        admin = bool(user and user.has_group('ff_base.group_ff_admin'))
        owner = self.employee_id.sudo()
        if self.state == 'manager':
            return admin or approver._ff_is_manager_of(owner)
        return admin or bool(user and owner.leave_manager_id == user)

    def ff_decide(self, approver, approve, reason=''):
        self.ensure_one()
        if not self._ff_awaits(approver):
            raise AccessError(self.env._('This cancellation is not waiting for you.'))
        rec = self.sudo()
        user = approver.sudo().user_id
        if not approve:
            rec.write({'state': 'rejected', 'decided_at': fields.Datetime.now()})
            rec._ff_tell_employee(self.env._('Your request to cancel the leave of %(date)s was not approved.',
                                             date=rec.leave_id.request_date_from))
            return rec
        if rec.state == 'manager':
            rec.manager_user_id = user.id or False
            rec._ff_after_manager()
        else:
            rec.hr_user_id = user.id or False
            rec._ff_finish()
        return rec

    def _ff_after_manager(self):
        self.ensure_one()
        hr_user = self.employee_id.sudo().leave_manager_id
        if self.levels == '2' and hr_user:
            self.write({'state': 'hr'})
            self._ff_notify_approver(hr_user.employee_id, user=hr_user)
        else:
            self._ff_finish()

    def _ff_finish(self):
        self.ensure_one()
        self.write({'state': 'done', 'decided_at': fields.Datetime.now()})
        self._ff_cancel_leave()
        self._ff_tell_employee(self.env._('Your leave of %(date)s was cancelled. You can work.',
                                          date=self.leave_id.request_date_from))

    def _ff_cancel_leave(self):
        self.ensure_one()
        leave = self.leave_id.sudo()
        if leave.state == 'validate':
            leave.with_context(ff_chain_finished=True).action_refuse()
        leave.message_post(body=self.env._('Cancelled at the employee\'s request%s.',
                                           (': ' + self.reason) if self.reason else ''))

    # ------------------------------------------------------------------ telling people
    def _ff_notify_approver(self, employee, user=None):
        if 'ff.notification' not in self.env:
            return
        self.env['ff.notification'].sudo().ff_push(
            title=self.env._('Leave Cancellation to Approve'),
            body=self.env._('%(employee)s wants to cancel the approved leave of %(date)s to work.',
                            employee=self.employee_id.name, date=self.leave_id.request_date_from),
            kind='approval', employee=employee or None, user=user, record=self.leave_id)

    def _ff_tell_employee(self, body):
        if 'ff.notification' in self.env:
            self.env['ff.notification'].sudo().ff_push(
                title=self.env._('Leave Cancellation'), body=body, kind='decision',
                employee=self.employee_id, record=self.leave_id)

    # ------------------------------------------------------------------ in Odoo
    def action_approve(self):
        approver = self.env.user.employee_id
        for rec in self:
            rec.ff_decide(approver, True)

    def action_reject(self):
        approver = self.env.user.employee_id
        for rec in self:
            rec.ff_decide(approver, False)
