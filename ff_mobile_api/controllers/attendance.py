from odoo import fields, http
from odoo.http import request

from odoo.addons.ff_attendance.models.ff_regularisation import REASONS
from odoo.addons.ff_base.tools import parse_client_dt

from .common import ApiError, api_route, attendance_data, body, ok, regularisation_data, check_device_clock


def _shift_data(employee, open_attendance, today):
    """The shift behind today's punch, so the app knows when the day is meant to end."""
    shift = (open_attendance.ff_shift_id if open_attendance else False) or employee.ff_shift_id
    if not shift:
        return None
    hours, minutes = divmod(min(int(round(shift.end_time * 60)), 24 * 60 - 1), 60)
    return {
        'id': shift.id,
        'name': shift.name,
        'start': round(shift.start_time, 2),
        'end': round(shift.end_time, 2),
        # Local wall-clock time the shift ends today, for the app to compare with.
        'ends_at': '%s %02d:%02d' % (today.isoformat(), hours, minutes),
        'half_day_hours': round(shift.half_day_hours, 2),
    }


class FieldForceAttendanceApi(http.Controller):

    @api_route('/api/v1/attendance/status', methods=('GET',))
    def status(self, employee, **kw):
        today = employee._ff_today()
        start, end = employee._ff_day_bounds(today)
        todays = request.env['hr.attendance'].sudo().search([
            ('employee_id', '=', employee.id), ('check_in', '>=', start), ('check_in', '<', end),
        ], order='check_in asc')
        open_att = employee._ff_open_attendance()
        return ok({
            'date': today.isoformat(),
            'punched_in': bool(open_att),
            'current': attendance_data(open_att),
            'today': [attendance_data(a) for a in todays],
            'worked_hours_today': round(sum(todays.mapped('worked_hours')), 2),
            'shift': _shift_data(employee, open_att, today),
        })

    @api_route('/api/v1/attendance/punch-in', methods=('POST',))
    def punch_in(self, employee, **kw):
        data = body()
        check_device_clock(employee, data, 'punch in')
        return ok(attendance_data(employee._ff_punch('in', data)))

    @api_route('/api/v1/attendance/punch-out', methods=('POST',))
    def punch_out(self, employee, **kw):
        data = body()
        check_device_clock(employee, data, 'punch out')
        return ok(attendance_data(employee._ff_punch('out', data)))

    @api_route('/api/v1/attendance/month', methods=('GET',))
    def month(self, employee, year=None, month=None, **kw):
        today = employee._ff_today()
        try:
            year = int(year or today.year)
            month = int(month or today.month)
        except ValueError:
            raise ApiError('year and month must be numbers.')
        if not 1 <= month <= 12:
            raise ApiError('month must be between 1 and 12.')
        return ok(employee._ff_attendance_month(year, month))

    @api_route('/api/v1/attendance/regularisations', methods=('GET',))
    def regularisations(self, employee, **kw):
        records = request.env['ff.regularisation'].sudo().search(
            [('employee_id', '=', employee.id)], limit=50)
        return ok([regularisation_data(r) for r in records])

    @api_route('/api/v1/attendance/regularisations', methods=('POST',))
    def create_regularisation(self, employee, **kw):
        data = body()
        try:
            day = fields.Date.to_date(data.get('date'))
            check_in = parse_client_dt(data.get('check_in'))
            check_out = parse_client_dt(data.get('check_out'))
        except (TypeError, ValueError):
            raise ApiError('date, check_in and check_out must be valid ISO dates.')
        if not (day and check_in and check_out):
            raise ApiError('date, check_in and check_out are required.')
        reason = data.get('reason') if data.get('reason') in dict(REASONS) else 'other'
        record = request.env['ff.regularisation'].sudo().create({
            'employee_id': employee.id,
            'date': day,
            'check_in': check_in,
            'check_out': check_out,
            'reason': reason,
            'note': data.get('note') or False,
        })
        record.action_submit()
        return ok(regularisation_data(record), status=201)
