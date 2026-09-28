"""Expense claims and travel allowances walk the chain when one is configured.

Without a flow they keep the single approval they always had, so a company that
does not need two signatures never sees the machinery.
"""
from odoo import api, models


class FfExpenseClaim(models.Model):
    _name = 'ff.expense.claim'
    _inherit = ['ff.expense.claim', 'ff.approvable.mixin']

    def action_submit(self):
        result = super().action_submit()
        self.filtered(lambda claim: claim.state == 'submitted')._ff_start_approval()
        return result

    def _ff_set_decision(self, approve, approver_user=False):
        """The plain decision, used at the end of a chain or when there is none."""
        return super()._ff_set_decision(approve, approver_user)

    def action_approve(self):
        return self._ff_chain_or_plain(True, super().action_approve)

    def action_reject(self):
        return self._ff_chain_or_plain(False, super().action_reject)

    def _ff_chain_or_plain(self, approve, plain):
        """Step through the chain when the document has one."""
        chained = self.filtered('approval_line_ids')
        for claim in chained:
            claim._ff_decide_step(self.env.user, approve)
        rest = self - chained
        if rest:
            return plain()
        return True

    def _ff_decide_as(self, employee, approve):
        """From the app: the person deciding is this employee's user."""
        self.ensure_one()
        if self.approval_line_ids:
            return self._ff_decide_step(employee.user_id, approve)
        return super()._ff_decide_as(employee, approve)

    @api.model
    def ff_waiting_for(self, user):
        """Claims this person is the current approver of."""
        lines = self.env['ff.approval.line'].sudo().search([
            ('res_model', '=', self._name), ('state', '=', 'pending'), ('user_id', '=', user.id),
        ])
        ids = [line.res_id for line in lines if line == line._ff_document().approval_line_ids.sorted(
            'sequence').filtered(lambda row: row.state == 'pending')[:1]]
        return self.sudo().browse(ids).exists()


class FfAllowanceClaim(models.Model):
    _name = 'ff.allowance.claim'
    _inherit = ['ff.allowance.claim', 'ff.approvable.mixin']

    def action_submit(self):
        result = super().action_submit()
        self.filtered(lambda claim: claim.state == 'submitted')._ff_start_approval()
        return result

    def action_approve(self):
        return self._ff_chain_or_plain(True, super().action_approve)

    def action_reject(self):
        return self._ff_chain_or_plain(False, super().action_reject)

    def _ff_chain_or_plain(self, approve, plain):
        chained = self.filtered('approval_line_ids')
        for claim in chained:
            claim._ff_decide_step(self.env.user, approve)
        rest = self - chained
        if rest:
            return plain()
        return True

    def _ff_decide_as(self, employee, approve):
        self.ensure_one()
        if self.approval_line_ids:
            return self._ff_decide_step(employee.user_id, approve)
        return super()._ff_decide_as(employee, approve)

    @api.model
    def ff_waiting_for(self, user):
        lines = self.env['ff.approval.line'].sudo().search([
            ('res_model', '=', self._name), ('state', '=', 'pending'), ('user_id', '=', user.id),
        ])
        ids = [line.res_id for line in lines if line == line._ff_document().approval_line_ids.sorted(
            'sequence').filtered(lambda row: row.state == 'pending')[:1]]
        return self.sudo().browse(ids).exists()
