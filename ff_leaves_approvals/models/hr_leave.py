"""Time off signed off by the approval chain, when one is configured for it.

Without a flow for Time Off nothing changes: Odoo's own leave approval runs as
before. With one, the request waits for each approver in turn - in Odoo or in
the app - and only the last "approve" validates the leave.
"""
from odoo import api, fields, models


class FfApprovalFlow(models.Model):
    _inherit = 'ff.approval.flow'

    document = fields.Selection(selection_add=[('hr.leave', 'Time Off')], ondelete={'hr.leave': 'cascade'})


class HrLeave(models.Model):
    _name = 'hr.leave'
    _inherit = ['hr.leave', 'ff.approvable.mixin']

    def _ff_chain_pending(self):
        return self.filtered(lambda leave: leave.approval_line_ids.filtered(lambda line: line.state == 'pending'))

    @api.model_create_multi
    def create(self, vals_list):
        leaves = super().create(vals_list)
        for leave in leaves.filtered(lambda l: l.state == 'confirm'):
            leave.sudo()._ff_start_approval()
        return leaves

    # -- the end of the chain: Odoo's own approval, all the way ------------
    def _ff_set_decision(self, approve, approver_user=False):
        for leave in self.sudo().with_context(ff_chain_finished=True):
            if approve:
                if leave.state == 'confirm':
                    leave.action_approve()
                if leave.state == 'validate1':
                    leave.action_validate()
            elif leave.state not in ('refuse', 'cancel'):
                leave.action_refuse()

    # -- Odoo's buttons step through the chain instead of skipping it -----
    def action_approve(self, *args, **kwargs):
        if self.env.context.get('ff_chain_finished'):
            return super().action_approve(*args, **kwargs)
        chained = self._ff_chain_pending()
        for leave in chained:
            leave._ff_decide_step(self.env.user, True)
        rest = self - chained
        return super(HrLeave, rest).action_approve(*args, **kwargs) if rest else True

    def action_validate(self, *args, **kwargs):
        if self.env.context.get('ff_chain_finished'):
            return super().action_validate(*args, **kwargs)
        chained = self._ff_chain_pending()
        for leave in chained:
            leave._ff_decide_step(self.env.user, True)
        rest = self - chained
        return super(HrLeave, rest).action_validate(*args, **kwargs) if rest else True

    def action_refuse(self, *args, **kwargs):
        if self.env.context.get('ff_chain_finished'):
            return super().action_refuse(*args, **kwargs)
        chained = self._ff_chain_pending()
        for leave in chained:
            leave._ff_decide_step(self.env.user, False)
        rest = self - chained
        return super(HrLeave, rest).action_refuse(*args, **kwargs) if rest else True

    def _ff_approval_payload(self):
        """With a chain, the steps are the chain's: who, and where it stands."""
        lines = self.sudo().approval_line_ids.sorted('sequence')
        if not lines:
            return super()._ff_approval_payload()
        return {
            'source': 'chain',
            'label': 'Approval flow: %d step%s' % (len(lines), '' if len(lines) == 1 else 's'),
            'steps': [{
                'name': line.name,
                'approver': line.user_id.name or '',
                'state': {'approved': 'done', 'rejected': 'rejected'}.get(line.state, line.state),
                'decided_at': fields.Datetime.to_string(line.decided_at) if line.decided_at else None,
                'note': line.note or '',
            } for line in lines],
        }

    # -- the app ----------------------------------------------------------
    def ff_decide_as(self, employee, approve, reason=''):
        self.ensure_one()
        if self._ff_chain_pending():
            self._ff_decide_step(employee.user_id, approve, reason)
            return self.sudo()
        return super().ff_decide_as(employee, approve, reason)

    @api.model
    def ff_to_approve(self, employee):
        """Leaves in a chain go to whoever the chain is waiting for; the rest to the manager as before."""
        user = employee.user_id
        plain = [row for row in super().ff_to_approve(employee)
                 if not self.sudo().browse(row['id'])._ff_chain_pending()]
        if not user:
            return plain
        lines = self.env['ff.approval.line'].sudo().search([
            ('res_model', '=', self._name), ('state', '=', 'pending'), ('user_id', '=', user.id)])
        waiting = []
        for line in lines:
            leave = line._ff_document()
            current = leave.approval_line_ids.sorted('sequence').filtered(lambda row: row.state == 'pending')[:1]
            if leave and current == line and leave.state in ('confirm', 'validate1'):
                payload = leave.ff_app_payload()
                payload['approval_step'] = '%s (%d of %d)' % (line.name, leave.approval_step + 1, leave.approval_total)
                waiting.append(payload)
        known = {row['id'] for row in plain}
        return plain + [row for row in waiting if row['id'] not in known]
