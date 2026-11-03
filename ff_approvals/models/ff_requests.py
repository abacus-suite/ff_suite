"""Payment requests wait for the approvers first (the manager, then anybody else the flow names); only then does the
accounts team see them to pay."""
from odoo import api, fields, models


class FfExpenseRequest(models.Model):
    _name = 'ff.expense.request'
    _inherit = ['ff.expense.request', 'ff.approvable.mixin']

    @api.model_create_multi
    def create(self, vals_list):
        requests = super().create(vals_list)
        for rec in requests:
            # A flow for payment requests puts the request with the approvers; without one it goes to accounts.
            if rec.state == 'requested' and rec.sudo()._ff_start_approval():
                rec.sudo().state = 'approval'
        return requests

    # -- Odoo's buttons
    def action_approve_step(self):
        for rec in self.filtered(lambda r: r.state == 'approval'):
            rec._ff_decide_step(self.env.user, True)

    def action_refuse_step(self):
        for rec in self.filtered(lambda r: r.state == 'approval'):
            rec._ff_decide_step(self.env.user, False, rec.reject_reason or '')

    def _ff_finish_approval(self, approved, user, note=''):
        self.ensure_one()
        if not approved and note:
            self.sudo().reject_reason = note
        super()._ff_finish_approval(approved, user, note)

    # -- the app
    def ff_decide_as(self, employee, approve, reason=''):
        self.ensure_one()
        self._ff_decide_step(employee.user_id, approve, reason)
        return self.sudo()

    @api.model
    def ff_to_approve(self, employee):
        """The requests whose current step is waiting for this person."""
        user = employee.user_id
        if not user:
            return self.browse()
        lines = self.env['ff.approval.line'].sudo().search([
            ('res_model', '=', self._name), ('state', '=', 'pending'), ('user_id', '=', user.id)])
        ids = []
        for line in lines:
            rec = line._ff_document()
            current = rec.approval_line_ids.sorted('sequence').filtered(lambda row: row.state == 'pending')[:1]
            if rec and rec.state == 'approval' and current == line:
                ids.append(rec.id)
        return self.sudo().browse(ids)
