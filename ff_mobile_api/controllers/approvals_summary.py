"""How much waits for a manager, by kind: the numbers on the Approvals button."""
from odoo import http
from odoo.http import request

from .common import api_route, ok


class FieldForceApprovalsSummaryApi(http.Controller):

    @api_route('/api/v1/approvals/summary', methods=('GET',), manager=True)
    def summary(self, employee):
        env = request.env
        team = employee._ff_subordinates()
        ids = team.ids

        def count(model, domain):
            if model not in env:
                return 0
            try:
                return env[model].sudo().search_count(domain)
            except Exception:  # noqa: BLE001 - one module's trouble must not hide the others
                return 0

        leaves = 0
        if 'hr.leave' in env and hasattr(env['hr.leave'], 'ff_to_approve'):
            try:
                leaves = len(env['hr.leave'].ff_to_approve(employee))
            except Exception:  # noqa: BLE001
                leaves = 0

        requests_count = 0
        if 'ff.expense.request' in env and hasattr(env['ff.expense.request'], 'ff_to_approve'):
            try:
                requests_count = len(env['ff.expense.request'].ff_to_approve(employee))
            except Exception:  # noqa: BLE001
                requests_count = 0
        elif 'ff.expense.request' in env:
            requests_count = count('ff.expense.request', [('employee_id', 'in', ids), ('state', '=', 'approval')])

        counts = {
            'contacts': count('res.partner', [('ff_is_client', '=', True), ('ff_approval_state', '=', 'pending'),
                                              ('ff_created_by_employee_id', 'in', ids)]),
            'access': count('ff.contact.access.request', [('employee_id', 'in', ids), ('state', '=', 'pending')]),
            'handovers': count('ff.distributor.handover', [('employee_id', 'in', ids), ('state', '=', 'handed')]),
            'deposits': count('ff.collection.deposit', [('employee_id', 'in', ids), ('state', '=', 'submitted')]),
            'notes': count('ff.distributor.note', [('employee_id', 'in', ids), ('state', '=', 'pending')]),
            'expenses': count('ff.expense.claim', [('employee_id', 'in', ids), ('state', '=', 'submitted')]),
            'requests': requests_count,
            'allowances': count('ff.allowance.claim', [('employee_id', 'in', ids), ('state', '=', 'submitted')]),
            'returns': count('ff.return', [('employee_id', 'in', ids), ('state', '=', 'submitted')]),
            'leaves': leaves,
            # A week of one person's daily allowance counts as one waiting item.
            'da': len(set(request.env['ff.da.claim'].sudo().search([
                ('employee_id', 'in', ids), ('state', '=', 'submitted')]).mapped(
                    lambda c: (c.employee_id.id, c.week_start)))) if 'ff.da.claim' in env else 0,
            'regularisation': count('ff.regularisation', [('employee_id', 'in', ids), ('state', '=', 'submitted')]),
            'beats': count('ff.beat', [('ff_approval_state', '=', 'pending'), ('ff_created_by_employee_id', 'in', ids)]),
        }
        return ok({'counts': counts, 'total': sum(counts.values())})
