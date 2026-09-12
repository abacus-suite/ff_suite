"""Leave endpoints for the Aixolo app."""
from odoo import http
from odoo.http import request

from odoo.addons.ff_mobile_api.controllers.clients import to_int
from odoo.addons.ff_mobile_api.controllers.common import ApiError, api_route, body, ok


class FieldForceLeavesApi(http.Controller):

    @api_route('/api/v1/leave-types', methods=('GET',))
    def types(self, employee, **kw):
        return ok(request.env['hr.leave'].ff_types_for(employee))

    @api_route('/api/v1/leaves', methods=('GET',))
    def leaves(self, employee, limit=None, **kw):
        Leave = request.env['hr.leave']
        rows = Leave.ff_my_leaves(employee, min(to_int(limit) or 50, 200))
        waiting = len([row for row in rows if row['state'] in ('confirm', 'validate1')])
        approved = len([row for row in rows if row['state'] == 'validate'])
        return ok({
            'summary': {'waiting': waiting, 'approved': approved, 'total': len(rows)},
            'types': Leave.ff_types_for(employee),
            'leaves': rows,
        })

    @api_route('/api/v1/leaves', methods=('POST',))
    def request_leave(self, employee, **kw):
        leave = request.env['hr.leave'].ff_request_from_app(employee, body())
        return ok(leave.ff_app_payload(), status=201)

    @api_route('/api/v1/leaves/<int:leave_id>', methods=('DELETE', 'POST'))
    def cancel(self, employee, leave_id, **kw):
        leave = request.env['hr.leave'].sudo().browse(leave_id).exists()
        if not leave:
            raise ApiError('Request not found.', 404, 'not_found')
        leave.ff_cancel_as(employee)
        return ok({'cancelled': True})

    @api_route('/api/v1/leaves/to-approve', methods=('GET',), manager=True)
    def to_approve(self, employee, **kw):
        return ok(request.env['hr.leave'].ff_to_approve(employee))

    @api_route('/api/v1/approvals/leave/<int:leave_id>/<string:decision>', methods=('POST',), manager=True)
    def decide(self, employee, leave_id, decision, **kw):
        if decision not in ('approve', 'reject'):
            raise ApiError('decision must be "approve" or "reject".')
        leave = request.env['hr.leave'].sudo().browse(leave_id).exists()
        if not leave:
            raise ApiError('Request not found.', 404, 'not_found')
        leave.ff_decide_as(employee, decision == 'approve', (body().get('reason') or '').strip())
        return ok(leave.ff_app_payload())
