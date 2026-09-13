import calendar
from datetime import date

from odoo import fields, models
from odoo.exceptions import UserError

from odoo.addons.ff_base.tools import get_settings, to_iso, client_time


def _strip_data_url(image):
    """Accept raw base64 or a ``data:image/...;base64,`` URL."""
    if image and isinstance(image, str) and image.startswith('data:') and ',' in image:
        return image.split(',', 1)[1]
    return image or False


class HrEmployee(models.Model):
    _inherit = 'hr.employee'

    ff_shift_id = fields.Many2one('ff.shift', string='Field Shift')

    def _ff_open_attendance(self):
        self.ensure_one()
        return self.env['hr.attendance'].sudo().search(
            [('employee_id', '=', self.id), ('check_out', '=', False)], order='check_in desc', limit=1)

    def _ff_sync_punch_status(self):
        Status = self.env['ff.employee.status']
        for employee in self:
            attendance = employee._ff_open_attendance()
            vals = {'punched_in': bool(attendance), 'punched_in_at': attendance.check_in or False}
            if not attendance:
                vals.update(is_inactive=False, is_signal_lost=False)
            Status._ff_get(employee).write(vals)

    def _ff_punch(self, action, data):
        """Punch ``action`` ('in' / 'out') from the mobile app.

        ``data`` keys: lat, lng, accuracy, mock, address, selfie (base64),
        battery, uuid, at. Server time is used, except for a punch queued offline:
        then ``at`` (the moment it happened) is kept and the record is flagged.
        """
        self.ensure_one()
        employee = self.sudo()
        uuid = data.get('uuid') or False
        if uuid:
            # The same punch sent twice (a retry after a lost answer) is the same punch.
            field = 'ff_in_uuid' if action == 'in' else 'ff_out_uuid'
            existing = self.env['hr.attendance'].sudo().search([(field, '=', uuid)], limit=1)
            if existing:
                return existing
        settings = get_settings(self.env)
        lat, lng = data.get('lat'), data.get('lng')
        if lat in (None, '') or lng in (None, ''):
            raise UserError(self.env._('Location is required to punch. Turn on GPS and try again.'))
        lat, lng = float(lat), float(lng)
        is_mock = bool(data.get('mock'))
        if is_mock and not settings['allow_mock']:
            self.env['ff.compliance.log'].ff_log(employee, [{'type': 'mock_location', 'detail': 'Blocked punch %s' % action}])
            raise UserError(self.env._('A fake GPS app was detected. Disable it to punch.'))
        selfie = _strip_data_url(data.get('selfie'))
        if settings['selfie_required'] and not selfie:
            raise UserError(self.env._('A selfie is required to punch.'))

        try:
            now, offline = client_time(data)
        except ValueError as error:
            raise UserError(str(error))
        accuracy = float(data.get('accuracy') or 0.0)
        address = (data.get('address') or '')[:250] or False
        attendance = employee._ff_open_attendance()
        if action == 'in':
            if attendance:
                raise UserError(self.env._('You are already punched in.'))
            attendance = self.env['hr.attendance'].sudo().create({
                'employee_id': employee.id,
                'check_in': now,
                'in_latitude': lat,
                'in_longitude': lng,
                'ff_in_address': address,
                'ff_in_accuracy': accuracy,
                'ff_in_is_mock': is_mock,
                'ff_in_selfie': selfie,
                'ff_source': 'app',
                'ff_in_uuid': uuid,
                'ff_offline': offline,
            })
        elif action == 'out':
            if not attendance:
                raise UserError(self.env._('You are not punched in.'))
            attendance.write({
                'check_out': now,
                'out_latitude': lat,
                'out_longitude': lng,
                'ff_out_address': address,
                'ff_out_accuracy': accuracy,
                'ff_out_is_mock': is_mock,
                'ff_out_selfie': selfie,
                'ff_out_uuid': uuid,
                'ff_offline': attendance.ff_offline or offline,
            })
        else:
            raise UserError(self.env._('Unknown punch action.'))

        self.env['ff.location.ping'].ff_ingest(employee, [{
            'lat': lat, 'lng': lng, 'accuracy': accuracy, 'battery': data.get('battery'),
            'mock': is_mock, 'source': 'punch', 'ts': fields.Datetime.to_string(now),
        }])
        if action == 'out':
            self.env['ff.daily.track']._ff_compute(employee, employee._ff_to_local(now).date())
        return attendance

    def _ff_attendance_month(self, year, month):
        """Day-by-day attendance summary of a month, for the app calendar."""
        self.ensure_one()
        employee = self.sudo()
        first = date(year, month, 1)
        last = date(year, month, calendar.monthrange(year, month)[1])
        start, _dummy = employee._ff_day_bounds(first)
        _dummy, end = employee._ff_day_bounds(last)
        attendances = self.env['hr.attendance'].sudo().search([
            ('employee_id', '=', employee.id), ('check_in', '>=', start), ('check_in', '<', end),
        ], order='check_in asc')

        by_day = {}
        for att in attendances:
            day = employee._ff_to_local(att.check_in).date()
            entry = by_day.setdefault(day, {
                'status': 'late' if att.ff_day_status == 'late' else 'present',
                'worked_hours': 0.0, 'first_in': att.check_in, 'last_out': False, 'open': False,
                'shift': att.ff_shift_id,
            })
            entry['worked_hours'] += att.worked_hours
            if att.check_out:
                entry['last_out'] = max(entry['last_out'] or att.check_out, att.check_out)
            else:
                entry['open'] = True

        today = employee._ff_today()
        shift = employee.ff_shift_id
        days, summary = [], {}
        for number in range(1, last.day + 1):
            day = date(year, month, number)
            entry = by_day.get(day)
            if entry:
                status = entry['status']
                half_day_hours = entry['shift'].half_day_hours if entry['shift'] else 0
                if not entry['open'] and day < today and entry['worked_hours'] < half_day_hours:
                    status = 'half_day'
            elif day > today:
                status = 'upcoming'
            elif shift._ff_is_week_off(day) if shift else day.weekday() == 6:
                status = 'week_off'
            elif day == today:
                status = 'not_punched'
            else:
                status = 'absent'
            summary[status] = summary.get(status, 0) + 1
            days.append({
                'date': day.isoformat(),
                'status': status,
                'worked_hours': round(entry['worked_hours'], 2) if entry else 0.0,
                'first_in': to_iso(entry['first_in']) if entry else None,
                'last_out': to_iso(entry['last_out']) if entry else None,
            })
        return {'year': year, 'month': month, 'days': days, 'summary': summary}
