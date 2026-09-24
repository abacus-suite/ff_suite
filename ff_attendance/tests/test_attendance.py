from datetime import datetime

from odoo.exceptions import AccessError, UserError
from odoo.tests import TransactionCase, new_test_user, tagged


@tagged('post_install', '-at_install', 'ff')
class TestFieldAttendance(TransactionCase):

    @classmethod
    def setUpClass(cls):
        super().setUpClass()
        cls.env['ir.config_parameter'].sudo().set_param('ff_base.selfie_required', 'False')
        cls.shift = cls.env['ff.shift'].create({
            'name': 'Test Shift', 'start_time': 9.0, 'end_time': 18.0,
            'grace_minutes': 10, 'half_day_hours': 4.0,
        })
        cls.employee = cls.env['hr.employee'].create({
            'name': 'Field Officer', 'tz': 'UTC', 'ff_shift_id': cls.shift.id,
        })
        cls.gps = {'lat': 10.0, 'lng': 76.0, 'accuracy': 8, 'address': 'MG Road'}

    def test_punch_in_and_out(self):
        attendance = self.employee._ff_punch('in', self.gps)
        self.assertFalse(attendance.check_out)
        self.assertEqual(attendance.ff_source, 'app')
        self.assertEqual(attendance.ff_shift_id, self.shift)
        status = self.env['ff.employee.status']._ff_get(self.employee)
        self.assertTrue(status.punched_in)

        with self.assertRaises(UserError):
            self.employee._ff_punch('in', self.gps)

        out = self.employee._ff_punch('out', self.gps)
        self.assertEqual(out, attendance)
        self.assertTrue(attendance.check_out)
        self.assertFalse(status.punched_in)

    def test_punch_rules(self):
        with self.assertRaises(UserError):
            self.employee._ff_punch('in', {'lat': None, 'lng': None})
        with self.assertRaises(UserError):
            self.employee._ff_punch('in', dict(self.gps, mock=True))
        self.env['ir.config_parameter'].sudo().set_param('ff_base.selfie_required', 'True')
        with self.assertRaises(UserError):
            self.employee._ff_punch('in', self.gps)

    def test_day_status(self):
        Attendance = self.env['hr.attendance']
        late_half = Attendance.create({
            'employee_id': self.employee.id,
            'check_in': datetime(2026, 1, 5, 9, 30),
            'check_out': datetime(2026, 1, 5, 11, 0),
        })
        self.assertEqual(late_half.ff_late_minutes, 30)
        self.assertEqual(late_half.ff_day_status, 'half_day')

        on_time = Attendance.create({
            'employee_id': self.employee.id,
            'check_in': datetime(2026, 1, 6, 9, 5),
            'check_out': datetime(2026, 1, 6, 18, 0),
        })
        self.assertEqual(on_time.ff_day_status, 'present')

        late = Attendance.create({
            'employee_id': self.employee.id,
            'check_in': datetime(2026, 1, 7, 9, 45),
            'check_out': datetime(2026, 1, 7, 18, 0),
        })
        self.assertEqual(late.ff_day_status, 'late')

        month = self.employee._ff_attendance_month(2026, 1)
        by_date = {d['date']: d['status'] for d in month['days']}
        self.assertEqual(by_date['2026-01-05'], 'half_day')
        self.assertEqual(by_date['2026-01-06'], 'present')
        self.assertEqual(by_date['2026-01-07'], 'late')
        self.assertEqual(by_date['2026-01-04'], 'week_off')  # Sunday
        self.assertEqual(by_date['2026-01-08'], 'absent')

    def test_regularisation_approval(self):
        manager_user = new_test_user(self.env, login='ff_test_manager',
                                     groups='base.group_user,ff_base.group_ff_manager')
        manager = self.env['hr.employee'].create({
            'name': 'Area Manager', 'user_id': manager_user.id, 'ff_access_scope': 'hierarchy',
        })
        self.employee.parent_id = manager
        officer_user = new_test_user(self.env, login='ff_test_officer',
                                     groups='base.group_user,ff_base.group_ff_officer')

        request = self.env['ff.regularisation'].create({
            'employee_id': self.employee.id,
            'date': '2026-01-08',
            'check_in': datetime(2026, 1, 8, 9, 0),
            'check_out': datetime(2026, 1, 8, 17, 0),
            'reason': 'battery',
        })
        request.action_submit()
        self.assertEqual(request.state, 'submitted')

        with self.assertRaises((AccessError, UserError)):
            request.with_user(officer_user).action_approve()

        request.with_user(manager_user).action_approve()
        self.assertEqual(request.state, 'approved')
        self.assertEqual(request.attendance_id.check_in, datetime(2026, 1, 8, 9, 0))
        self.assertEqual(request.attendance_id.ff_source, 'regularisation')

    def test_offline_punch_is_idempotent_and_keeps_time(self):
        from datetime import datetime, timedelta, timezone
        started = (datetime.now(timezone.utc) - timedelta(hours=4)).replace(microsecond=0)
        data = dict(self.gps, uuid='punch-in-1', at=started.isoformat())
        attendance = self.employee._ff_punch('in', data)
        self.assertTrue(attendance.ff_offline)
        self.assertEqual(attendance.check_in, started.replace(tzinfo=None))
        self.assertEqual(self.employee._ff_punch('in', data), attendance)
        out = self.employee._ff_punch('out', dict(self.gps, uuid='punch-out-1', at=(started + timedelta(hours=3)).isoformat()))
        self.assertEqual(out, attendance)
        self.assertAlmostEqual(attendance.worked_hours, 3.0, delta=0.05)
