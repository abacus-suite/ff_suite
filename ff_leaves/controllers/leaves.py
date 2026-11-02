"""Leave endpoints for the Field Force app."""
from datetime import timedelta

from odoo import fields, http
from odoo.exceptions import AccessError, UserError
from odoo.http import request

from odoo.addons.ff_mobile_api.controllers.clients import to_int
from odoo.addons.ff_mobile_api.controllers.common import ApiError, api_route, body, note_rejection, ok


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
        types = Leave.ff_types_for(employee)
        return ok({
            'summary': {
                'waiting': waiting, 'approved': approved, 'total': len(rows),
                'allocated': round(sum(t['allocated'] or 0 for t in types), 2),
                'used': round(sum(t['used'] or 0 for t in types), 2),
                'pending': round(sum(t['pending'] or 0 for t in types), 2),
                'remaining': round(sum(t['remaining'] or 0 for t in types if t['requires_allocation']), 2),
            },
            'types': types,
            'allocations': Leave.ff_allocations_for(employee),
            'holidays': self._holidays(employee),
            'leaves': rows,
        })

    @staticmethod
    def _holidays(employee):
        """The company's coming days off that apply to this employee, soonest first."""
        if 'ff.holiday' not in request.env:
            return []
        today = employee._ff_today()
        rows = request.env['ff.holiday'].sudo().search([
            ('date', '>=', today), ('date', '<=', today + timedelta(days=120)),
            ('company_id', 'in', (False, employee.company_id.id)),
        ], order='date')
        return [{'id': h.id, 'name': h.name, 'date': h.date.isoformat()}
                for h in rows if request.env['ff.holiday']._ff_for(employee, h.date) == h][:8]

    @api_route('/api/v1/leaves/team', methods=('GET',), manager=True)
    def team(self, employee, **kw):
        return ok(request.env['hr.leave'].ff_team_balances(employee))

    @api_route('/api/v1/leaves/calendar', methods=('GET',))
    def calendar(self, employee, start=None, end=None, member=None, **kw):
        today = employee._ff_today()
        low = fields.Date.to_date(start) if start else today.replace(day=1)
        high = fields.Date.to_date(end) if end else low + timedelta(days=41)
        if (high - low).days > 120:
            raise ApiError('Choose a range of 120 days or less.')
        return ok({'start': low.isoformat(), 'end': high.isoformat(),
                   'leaves': request.env['hr.leave'].ff_calendar(employee, low, high, member)})

    @api_route('/api/v1/leaves/check', methods=('GET',))
    def check(self, employee, start=None, end=None, **kw):
        low = fields.Date.to_date(start) if start else employee._ff_today()
        high = fields.Date.to_date(end) if end else low
        if high < low:
            low, high = high, low
        return ok({'warnings': request.env['hr.leave'].ff_check_overlap(employee, low, high)})

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

    @api_route('/api/v1/leaves/today', methods=('GET',))
    def today_leave(self, employee, **kw):
        """The approved leave that covers today, asked at check-in: the employee may cancel it to work."""
        today = employee._ff_today()
        leave = request.env['hr.leave'].sudo().search([
            ('employee_id', '=', employee.id), ('state', '=', 'validate'),
            ('request_date_from', '<=', today), ('request_date_to', '>=', today)], limit=1)
        Cancel = request.env['ff.leave.cancel'].sudo()
        waiting = bool(leave and Cancel.search_count([('leave_id', '=', leave.id), ('state', 'in', ('manager', 'hr'))]))
        return ok({
            'leave': leave.ff_app_payload() if leave else None,
            'cancel_requested': waiting,
            'needs_approval': Cancel._ff_needs_approval(),
            'levels': int(Cancel._ff_levels()),
        })

    @api_route('/api/v1/leaves/<int:leave_id>/cancel-approved', methods=('POST',))
    def cancel_approved(self, employee, leave_id, **kw):
        leave = request.env['hr.leave'].sudo().browse(leave_id).exists()
        if not leave:
            raise ApiError('Request not found.', 404, 'not_found')
        try:
            rec = request.env['ff.leave.cancel'].ff_request(employee, leave, (body().get('reason') or '').strip())
        except (UserError, AccessError) as error:
            request.env.cr.rollback()
            raise ApiError(str(error), 400, 'invalid')
        return ok({'state': rec.state, 'cancelled': rec.state == 'done'})

    @api_route('/api/v1/approvals/leave/<int:leave_id>/<string:decision>', methods=('POST',), manager=True)
    def decide(self, employee, leave_id, decision, **kw):
        if decision not in ('approve', 'reject'):
            raise ApiError('decision must be "approve" or "reject".')
        leave = request.env['hr.leave'].sudo().browse(leave_id).exists()
        if not leave:
            raise ApiError('Request not found.', 404, 'not_found')
        # A cancellation of an approved leave that is waiting for this person.
        cancel = request.env['ff.leave.cancel'].ff_pending_for(leave, employee)
        if cancel:
            try:
                cancel.ff_decide(employee, decision == 'approve', (body().get('reason') or '').strip())
            except (UserError, AccessError) as error:
                request.env.cr.rollback()
                raise ApiError(str(error), 400, 'invalid')
            return ok(leave.ff_app_payload())
        leave.ff_decide_as(employee, decision == 'approve', (body().get('reason') or '').strip())
        note_rejection(leave, decision == 'approve', employee)
        return ok(leave.ff_app_payload())
