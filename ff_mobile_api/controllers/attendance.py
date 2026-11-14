from odoo import fields, http
from odoo.http import request

from odoo.addons.ff_attendance.models.ff_regularisation import REASONS
from odoo.addons.ff_base.tools import get_settings, parse_client_dt, to_iso

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
        settings = get_settings(request.env)
        today = employee._ff_today()
        start, end = employee._ff_day_bounds(today)
        todays = request.env['hr.attendance'].sudo().search([
            ('employee_id', '=', employee.id), ('check_in', '>=', start), ('check_in', '<', end),
        ], order='check_in asc')
        open_att = employee._ff_open_attendance()
        # The last meter reading on record, so a check-in reading below it can be caught on the phone.
        last = request.env['hr.attendance'].sudo().search([
            ('employee_id', '=', employee.id), '|', ('ff_out_odometer', '>', 0), ('ff_in_odometer', '>', 0),
        ], order='check_in desc', limit=1)
        return ok({
            'date': today.isoformat(),
            'odometer_last': (last.ff_out_odometer or last.ff_in_odometer) if last and (not open_att or last != open_att) else None,
            'punched_in': bool(open_att),
            'current': attendance_data(open_att),
            'today': [attendance_data(a) for a in todays],
            'worked_hours_today': round(sum(todays.mapped('worked_hours')), 2),
            'shift': _shift_data(employee, open_att, today),
            'punch_count': len(todays),
            'last_check_out': to_iso(todays[-1:].check_out) if todays and todays[-1:].check_out else None,
            # Checked out but the day may be picked up again: the app offers Resume.
            'can_resume': bool(todays) and not open_att and not settings['single_punch_day'],
            'duty_check_minutes': settings['duty_check_minutes'],
            'duty_reply_minutes': settings['duty_reply_minutes'],
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

    @staticmethod
    def _recorded_day(employee, day):
        """What was recorded for ``day``: the first punch in and the last punch out (None while it is missing)."""
        start, end = employee._ff_day_bounds(day)
        rows = request.env['hr.attendance'].sudo().search([
            ('employee_id', '=', employee.id), ('check_in', '>=', start), ('check_in', '<', end)], order='check_in')
        if not rows:
            return None, None
        outs = rows.filtered('check_out')
        return rows[0].check_in, (outs[-1].check_out if outs and not rows.filtered(lambda r: not r.check_out) else None)

    @api_route('/api/v1/attendance/day', methods=('GET',))
    def recorded_day(self, employee, date=None, **kw):
        """The punches recorded on a day, shown on the correction form."""
        try:
            day = fields.Date.to_date(date) if date else employee._ff_today()
        except ValueError:
            raise ApiError('date must be YYYY-MM-DD.')
        today = employee._ff_today()
        check_in, check_out = self._recorded_day(employee, day)
        pending = request.env['ff.regularisation'].sudo().search([
            ('employee_id', '=', employee.id),
            ('date', '=', day),
            ('state', 'in', ('draft', 'submitted')),
        ], order='id desc')
        pending_list = [regularisation_data(p) for p in pending]
        return ok({
            'date': day.isoformat(),
            'check_in': to_iso(check_in),
            'check_out': to_iso(check_out),
            'is_future': day > today,
            'has_pending': bool(pending),
            'pending_requests': pending_list,
        })

    @api_route('/api/v1/attendance/regularisations', methods=('GET',))
    def regularisations(self, employee, **kw):
        records = request.env['ff.regularisation'].sudo().search(
            [('employee_id', '=', employee.id)], limit=50)
        return ok([regularisation_data(r) for r in records])

    @api_route('/api/v1/attendance/regularisations', methods=('POST',))
    def create_regularisation(self, employee, **kw):
        data = body()
        which = data.get('which') if data.get('which') in ('in', 'out') else 'both'
        try:
            day = fields.Date.to_date(data.get('date'))
            today = employee._ff_today()
            if day and day > today:
                raise ApiError('Attendance correction cannot be requested for future dates.', 400, 'future_date')
            if which == 'both':
                check_in = parse_client_dt(data.get('check_in'))
                check_out = parse_client_dt(data.get('check_out'))
            else:
                # One punch only: it is sent as its own request; the other punch of the day can be a request of its own.
                corrected = parse_client_dt(data.get('time'))
                if not corrected:
                    raise ApiError('Enter the correct time.')
                check_in, check_out = (corrected, False) if which == 'in' else (False, corrected)
        except (TypeError, ValueError):
            raise ApiError('date and the time must be valid ISO dates.')
        if not day or not (check_in or check_out) or (which == 'both' and not (check_in and check_out)):
            raise ApiError('date, check_in and check_out are required.')
        note = (data.get('note') or '').strip()
        if which != 'both' and not note:
            raise ApiError('Give the reason for the correction.')

        # Check for existing pending regularisations on the same day for this punch
        existing_domain = [
            ('employee_id', '=', employee.id),
            ('date', '=', day),
            ('state', 'in', ('draft', 'submitted')),
        ]
        if which == 'in':
            existing_domain.append(('which', 'in', ('in', 'both')))
        elif which == 'out':
            existing_domain.append(('which', 'in', ('out', 'both')))
        conflict = request.env['ff.regularisation'].sudo().search(existing_domain, limit=1)
        if conflict:
            punch_type = 'check-in' if conflict.which == 'in' else ('check-out' if conflict.which == 'out' else 'attendance')
            raise ApiError(
                f'A {punch_type} correction request for {day} is already pending approval. Please wait until it is approved or rejected.',
                400, 'already_pending'
            )

        reason = data.get('reason') if data.get('reason') in dict(REASONS) else 'other'
        record = request.env['ff.regularisation'].sudo().create({
            'employee_id': employee.id,
            'date': day,
            'check_in': check_in,
            'check_out': check_out,
            'which': which,
            'reason': reason,
            'note': note or False,
        })
        record.action_submit()
        return ok(regularisation_data(record), status=201)
