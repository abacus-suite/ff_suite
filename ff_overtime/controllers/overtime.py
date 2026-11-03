"""Overtime in the app: the days with overtime, sending them, and the manager's decision."""
from datetime import date as date_type
import calendar

from odoo import fields
from odoo.http import request

from odoo.addons.ff_base.tools import to_iso
from odoo.addons.ff_mobile_api.controllers.common import ApiError, api_route, body, ok, ref
from odoo import http
from odoo.exceptions import AccessError, UserError


def _row(rec):
    return {
        'id': rec.id, 'date': to_iso(rec.date), 'worked_minutes': rec.worked_minutes,
        'expected_minutes': rec.expected_minutes, 'overtime_minutes': rec.overtime_minutes,
        'approved_minutes': rec.approved_minutes, 'state': rec.state, 'note': rec.decision_note or None,
        'employee': ref(rec.employee_id),
    }


class FieldForceOvertimeApi(http.Controller):

    @api_route('/api/v1/overtime', methods=('GET',))
    def listing(self, employee, month=None, **kw):
        try:
            year, number = (int(p) for p in str(month).split('-')[:2]) if month else (None, None)
        except ValueError:
            raise ApiError('month must be YYYY-MM.')
        today = employee._ff_today()
        first = date_type(year or today.year, number or today.month, 1)
        last = date_type(first.year, first.month, calendar.monthrange(first.year, first.month)[1])
        Overtime = request.env['ff.overtime']
        Overtime._ff_refresh(employee, first, min(last, today))
        rows = Overtime.sudo().search([('employee_id', '=', employee.id), ('date', '>=', first), ('date', '<=', last)],
                                      order='date desc')
        return ok({
            'month': first.strftime('%Y-%m'),
            'rows': [_row(r) for r in rows],
            'to_send_minutes': sum(r.overtime_minutes for r in rows if r.state == 'draft'),
            'waiting_minutes': sum(r.overtime_minutes for r in rows if r.state == 'submitted'),
            'approved_minutes': sum(r.approved_minutes for r in rows if r.state == 'approved'),
        })

    @api_route('/api/v1/overtime/send', methods=('POST',))
    def send(self, employee, **kw):
        ids = [int(i) for i in (body().get('ids') or [])]
        rows = request.env['ff.overtime'].sudo().search([('id', 'in', ids)]) if ids else \
            request.env['ff.overtime'].sudo().search([('employee_id', '=', employee.id), ('state', '=', 'draft')])
        try:
            rows.ff_send(employee)
        except UserError as error:
            request.env.cr.rollback()
            raise ApiError(str(error), 400, 'invalid')
        return ok({'sent': len(rows)})

    @api_route('/api/v1/overtime/to-approve', methods=('GET',), manager=True)
    def to_approve(self, employee, **kw):
        team = employee._ff_approval_team()
        rows = request.env['ff.overtime'].sudo().search(
            [('employee_id', 'in', team.ids), ('state', '=', 'submitted')], order='date desc')
        return ok({'rows': [_row(r) for r in rows]})

    @api_route('/api/v1/overtime/<int:overtime_id>/decide', methods=('POST',), manager=True)
    def decide(self, employee, overtime_id, **kw):
        rec = request.env['ff.overtime'].sudo().browse(overtime_id).exists()
        if not rec:
            raise ApiError('Overtime not found.', 404, 'not_found')
        data = body()
        try:
            rec.ff_decide(employee, data.get('minutes'), reject=bool(data.get('reject')),
                          note=(data.get('reason') or '').strip())
        except (UserError, AccessError) as error:
            request.env.cr.rollback()
            raise ApiError(str(error), 400, 'invalid')
        return ok(_row(rec))
