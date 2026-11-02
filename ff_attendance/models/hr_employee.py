import calendar
from datetime import date, datetime, timedelta

import pytz

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

    def write(self, vals):
        res = super().write(vals)
        if 'ff_shift_id' in vals:
            shift_id = vals['ff_shift_id']
            for employee in self:
                today = employee._ff_today()
                start, end = employee._ff_day_bounds(today)
                attendances = self.env['hr.attendance'].sudo().search([
                    ('employee_id', '=', employee.id),
                    '|',
                    ('ff_shift_id', '=', False),
                    '&', ('check_in', '>=', start), ('check_in', '<', end),
                ])
                if attendances:
                    attendances.write({'ff_shift_id': shift_id})
        return res

    def _ff_keeps_punch_open(self):
        """An event day is being worked, or was closed only now in the small hours: the open punch is left alone.

        While the day of a running event is not closed the person cannot check out, and neither can the day be closed
        for them at midnight. Once they close it they check out themselves (even after midnight), and check in again
        the same morning: that morning's attendance starts at the new check-in.
        """
        self.ensure_one()
        if 'ff.event' not in self.env:
            return False
        mine = ['|', ('employee_id', '=', self.id), ('staff_ids', 'in', self.ids)]
        if self.env['ff.event'].sudo().search_count([('state', '=', 'running')] + mine):
            return True
        now = datetime.now(pytz.utc).astimezone(self._ff_tz())
        if now.hour < 6:
            yesterday = now.date() - timedelta(days=1)
            return bool(self.env['ff.event.day'].sudo().search_count([
                ('date', '=', yesterday), '|', ('event_id.employee_id', '=', self.id),
                ('event_id.staff_ids', 'in', self.ids)]))
        return False

    def _ff_open_attendance(self):
        self.ensure_one()
        open_att = self.env['hr.attendance'].sudo().search(
            [('employee_id', '=', self.id), ('check_out', '=', False)], order='check_in desc', limit=1)
        if open_att and open_att.check_in:
            local_in = self._ff_to_local(open_att.check_in)
            if local_in.date() < self._ff_today() and not self._ff_keeps_punch_open():
                # Past-day punch left open: auto-close it now so today starts clean
                self.env['hr.attendance']._close_attendance_record(open_att, reason='midnight')
                return self.env['hr.attendance'].browse()
        return open_att

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
            # A day the app closes by itself has no fresh fix: the last known
            # position stands in, so the day can still be closed properly.
            if action == 'out' and data.get('auto'):
                last = self.env['ff.location.ping'].sudo().search(
                    [('employee_id', '=', employee.id)], order='ts desc', limit=1)
                lat, lng = (last.latitude, last.longitude) if last else (0.0, 0.0)
            else:
                raise UserError(self.env._('Location is required to punch. Turn on GPS and try again.'))
        lat, lng = float(lat), float(lng)
        is_mock = bool(data.get('mock'))
        if is_mock and not settings['allow_mock']:
            self.env['ff.compliance.log'].ff_log(employee, [{'type': 'mock_location', 'detail': 'Blocked punch %s' % action}])
            raise UserError(self.env._('A fake GPS app was detected. Disable it to punch.'))
        selfie = _strip_data_url(data.get('selfie'))
        # A day the app closes by itself has nobody to take a selfie or read the meter.
        by_app = action == 'out' and bool(data.get('auto'))
        if settings['selfie_required'] and not selfie and not by_app:
            raise UserError(self.env._('A selfie is required to punch.'))
        odometer_photo = _strip_data_url(data.get('odometer_photo'))
        odometer = data.get('odometer')
        try:
            odometer = float(odometer) if odometer not in (None, '') else False
        except (TypeError, ValueError):
            raise UserError(self.env._('The odometer reading must be a number.'))
        vehicle = data.get('vehicle') or False
        if vehicle and vehicle not in dict(self.env['hr.attendance']._fields['ff_vehicle_type'].selection):
            raise UserError(self.env._('That vehicle is not one of the choices.'))
        vehicle_owner = data.get('vehicle_owner') or False
        if vehicle_owner and 'ff_vehicle_owner' in self.env['hr.attendance']._fields and vehicle_owner not in dict(self.env['hr.attendance']._fields['ff_vehicle_owner'].selection):
            vehicle_owner = False
        vehicle_note = (data.get('vehicle_note') or '').strip()[:120]
        if vehicle == 'other' and not vehicle_note:
            raise UserError(self.env._('Say in a few words how you are travelling today.'))
        open_attendance = employee._ff_open_attendance()
        # Only somebody on their own two- or four-wheeler has a meter to photograph.
        # A company scooter has no meter to read or photograph.
        owner_now = vehicle_owner or (getattr(open_attendance, 'ff_vehicle_owner', False) if open_attendance else False)
        is_company_vehicle = (owner_now == 'company')
        on_own_vehicle = (vehicle or (open_attendance.ff_vehicle_type if open_attendance else False))             in ('two_wheeler', 'four_wheeler') and not is_company_vehicle
        if settings['punch_odometer'] and on_own_vehicle and not (odometer_photo and odometer) and not by_app:
            raise UserError(self.env._('A photo of the odometer and its reading are required to punch.'))

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
            # Choose Beat at Check-in is on: a beat must be chosen for the day before checking in.
            if getattr(employee, 'ff_beat_at_checkin', False) and 'ff.beat.plan' in self.env:
                day = employee._ff_to_local(now).date()
                if (not self.env['ff.beat.plan'].sudo().search_count([('employee_id', '=', employee.id), ('date', '=', day)])
                        and self.env['ff.beat.plan'].ff_app_routes(employee)):
                    raise UserError(self.env._('Choose your beat for today before you check in.'))
            if settings['single_punch_day']:
                start_of_day, end_of_day = employee._ff_day_bounds(employee._ff_to_local(now).date())
                closed = self.env['hr.attendance'].sudo().search_count([
                    ('employee_id', '=', employee.id), ('check_in', '>=', start_of_day),
                    ('check_in', '<', end_of_day), ('check_out', '!=', False)])
                if closed:
                    raise UserError(self.env._(
                        'Your day is already closed. The office allows one check-in a day; '
                        'ask them to reopen it if you need to work again today.'))
            if odometer:
                # The meter only goes up: a reading below the last one on record was mistyped.
                last = self.env['hr.attendance'].sudo().search([
                    ('employee_id', '=', employee.id), '|', ('ff_out_odometer', '>', 0), ('ff_in_odometer', '>', 0),
                ], order='check_in desc', limit=1)
                before = last.ff_out_odometer or last.ff_in_odometer
                if before and odometer < before:
                    raise UserError(self.env._(
                        'The opening reading %(now)s is less than your last closing reading, %(before)s. '
                        'The meter cannot go backwards: please enter the correct reading.',
                        now=odometer, before=before))
            attendance = self.env['hr.attendance'].sudo().create({
                'employee_id': employee.id,
                'check_in': now,
                'in_latitude': lat,
                'in_longitude': lng,
                'ff_in_address': address,
                'ff_in_accuracy': accuracy,
                'ff_in_is_mock': is_mock,
                'ff_in_selfie': selfie,
                'ff_vehicle_type': vehicle,
                'ff_vehicle_owner': vehicle_owner if 'ff_vehicle_owner' in self.env['hr.attendance']._fields else False,
                'ff_vehicle_note': vehicle_note or False,
                'ff_in_odometer': odometer or 0.0,
                'ff_in_odometer_photo': odometer_photo,
                'ff_source': 'app',
                'ff_in_uuid': uuid,
                'ff_offline': offline,
            })
        elif action == 'out':
            if not attendance:
                raise UserError(self.env._('You are not punched in.'))
            if 'ff.event' in self.env:
                # An event that is running (its day not ended) keeps the person checked in - for an automatic
                # check-out too.
                running = self.env['ff.event'].sudo().search([
                    ('state', '=', 'running'), '|', ('employee_id', '=', employee.id),
                    ('staff_ids', 'in', employee.ids)], limit=1)
                if running:
                    raise UserError(self.env._(
                        "You can't check out yet. %s is still running. Complete End of the Day "
                        "(or End of the Event on the last day) before you check out.", running.name))
            early = attendance._ff_early_minutes(now)
            reason = (data.get('early_reason') or '').strip()[:250]
            if settings['early_checkout_reason'] and early > 0 and not reason and not data.get('auto'):
                raise UserError(self.env._(
                    'Your shift ends later. Say why you are ending the day now.'))
            if odometer and attendance.ff_in_odometer and odometer < attendance.ff_in_odometer:
                raise UserError(self.env._(
                    'The closing reading %(now)s is less than the opening reading %(before)s. '
                    'A negative distance is not allowed: please enter the correct reading.',
                    now=odometer, before=attendance.ff_in_odometer))
            attendance.write({
                'check_out': now,
                'out_latitude': lat,
                'out_longitude': lng,
                'ff_out_address': address,
                'ff_out_accuracy': accuracy,
                'ff_out_is_mock': is_mock,
                'ff_out_selfie': selfie,
                'ff_auto_closed': bool(data.get('auto')),
                'ff_close_reason': data.get('close_reason') if data.get('auto') else False,
                'ff_early_minutes': early,
                'ff_early_reason': reason or False,
                'ff_out_odometer': odometer or 0.0,
                'ff_out_odometer_photo': odometer_photo,
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
            shift = att.ff_shift_id or att.employee_id.ff_shift_id
            is_late = att.ff_day_status == 'late' or (getattr(att, 'ff_late_minutes', 0) > (shift.grace_minutes if shift else 0))
            entry = by_day.setdefault(day, {
                'status': 'late' if is_late else 'present',
                'worked_hours': 0.0, 'first_in': att.check_in, 'last_out': False, 'open': False,
                'shift': shift,
            })
            entry['worked_hours'] += att.worked_hours
            if att.check_out:
                entry['last_out'] = max(entry['last_out'] or att.check_out, att.check_out)
            else:
                entry['open'] = True

        # Approved time off: every day it covers, in the employee's local time.
        leave_days = set()
        if 'hr.leave' in self.env:
            for leave in self.env['hr.leave'].sudo().search([
                    ('employee_id', '=', employee.id), ('state', '=', 'validate'),
                    ('date_from', '<', end), ('date_to', '>=', start)]):
                day = employee._ff_to_local(leave.date_from).date()
                until = employee._ff_to_local(leave.date_to).date()
                while day <= until:
                    leave_days.add(day)
                    day += timedelta(days=1)
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
            elif day in leave_days:
                status = 'leave'
            elif self.env['ff.holiday']._ff_for(employee, day):
                # Before "upcoming", so a holiday still to come is shown as one.
                status = 'holiday'
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
                'holiday': self.env['ff.holiday']._ff_for(employee, day).name or None if status == 'holiday' else None,
            })
        return {'year': year, 'month': month, 'days': days, 'summary': summary}
