"""Payment requests wait for the approvers first (the manager, then anybody else the flow names); only then does the
accounts team see them to pay.

The manager's approval does not depend on a flow having been set up: a request always starts with the manager. The flow
only adds the steps that come after (or instead of) the reporting manager."""
from odoo import api, models
from odoo.exceptions import AccessError, UserError


class FfExpenseRequest(models.Model):
    _name = 'ff.expense.request'
    _inherit = ['ff.expense.request', 'ff.approvable.mixin']

    @api.model_create_multi
    def create(self, vals_list):
        requests = super().create(vals_list)
        mode = self.env['ir.config_parameter'].sudo().get_param('ff_expenses.request_approval_levels') or 'manager'
        for rec in requests.sudo():
            if rec.state != 'requested':
                continue
            started = rec._ff_start_approval()
            # With a flow the chain asks the approvers; without one the reporting manager still has to approve.
            # In manager-only mode it always starts with approval. In two-level mode, a request with nobody to ask
            # goes straight to accounts.
            if started or rec.employee_id.parent_id or mode == 'manager':
                rec.state = 'approval'
                if not started:
                    rec._ff_notify_manager()
        return requests

    def _ff_notify_approver(self, line):
        self.ensure_one()
        if not line.user_id:
            return
        approver_user = line.user_id
        approver_emp = approver_user.sudo().employee_id
        if not approver_emp:
            approver_emp = self.env['hr.employee'].sudo().search([('user_id', '=', approver_user.id)], limit=1)
        if not approver_emp:
            approver_emp = self.employee_id.parent_id

        currency_symbol = self.currency_id.symbol or '₹'
        category_name = self.category_id.name or 'Expense'
        if self.sub_category_id:
            category_name = f"{category_name} - {self.sub_category_id.name}"
        title = self.env._('Payment Request to Approve')
        body = self.env._(
            '%(employee)s requested payment of %(symbol)s%(amount).2f for %(category)s.',
            employee=self.employee_id.name,
            symbol=currency_symbol,
            amount=self.amount,
            category=category_name,
        )
        self.sudo().message_post(body=body, partner_ids=approver_user.partner_id.ids)
        if 'ff.notification' in self.env:
            self.env['ff.notification'].sudo().ff_push(
                user=approver_user,
                employee=approver_emp or None,
                title=title,
                body=body,
                kind='approval',
                record=self,
            )

    def _ff_pending_line(self):
        self.ensure_one()
        return self.approval_line_ids.sorted('sequence').filtered(lambda line: line.state == 'pending')[:1]

    def _ff_plain_decision(self, approver, approve, note=''):
        """No chain to walk: the reporting manager (or an administrator) decides."""
        self.ensure_one()
        user = approver.sudo().user_id
        admin = bool(user and user.has_group('ff_base.group_ff_admin'))
        if not admin and not approver._ff_is_manager_of(self.employee_id):
            raise AccessError(self.env._('This request is not yours to decide.'))
        if self.state != 'approval':
            raise UserError(self.env._('This request is not waiting for an approval.'))
        if not approve and note:
            self.sudo().reject_reason = note
        self._ff_set_decision(approve, user.id if user else False)
        self._ff_notify_owner(approve, note)

    # -- Odoo's buttons
    def action_approve_step(self):
        for rec in self.filtered(lambda r: r.state == 'approval'):
            if rec._ff_pending_line():
                rec._ff_decide_step(self.env.user, True)
            else:
                rec._ff_plain_decision(self.env.user.employee_id, True)

    def action_refuse_step(self):
        for rec in self.filtered(lambda r: r.state == 'approval'):
            if rec._ff_pending_line():
                rec._ff_decide_step(self.env.user, False, rec.reject_reason or '')
            else:
                rec._ff_plain_decision(self.env.user.employee_id, False, rec.reject_reason or '')

    def _ff_finish_approval(self, approved, user, note=''):
        self.ensure_one()
        if not approved and note:
            self.sudo().reject_reason = note
        super()._ff_finish_approval(approved, user, note)

    # -- the app
    def ff_decide_as(self, employee, approve, reason=''):
        self.ensure_one()
        if self._ff_pending_line():
            self._ff_decide_step(employee.user_id, approve, reason)
        else:
            self._ff_plain_decision(employee, approve, reason)
        return self.sudo()

    @api.model
    def ff_to_approve(self, employee):
        """The requests waiting for this person: the current step of a chain, or - with no chain - the requests of the
        people reporting to them."""
        ids = set()
        user = employee.user_id
        if user:
            lines = self.env['ff.approval.line'].sudo().search([
                ('res_model', '=', self._name), ('state', '=', 'pending'), ('user_id', '=', user.id)])
            for line in lines:
                rec = line._ff_document()
                if rec and rec.state == 'approval' and rec._ff_pending_line() == line:
                    ids.add(rec.id)
        team = employee._ff_approval_team()
        if team:
            for rec in self.sudo().search([('state', '=', 'approval'), ('employee_id', 'in', team.ids)]):
                if not rec._ff_pending_line():
                    ids.add(rec.id)
        return self.sudo().browse(sorted(ids))
