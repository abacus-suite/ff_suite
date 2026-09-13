from datetime import datetime, timedelta, timezone

from odoo.tests import TransactionCase, tagged

from odoo.addons.ff_base.tools import clock_skew_minutes, client_time


@tagged('post_install', '-at_install', 'ff')
class TestClientTime(TransactionCase):

    def test_now_without_at(self):
        at, offline = client_time({})
        self.assertFalse(offline)
        self.assertLess(abs((datetime.now(timezone.utc).replace(tzinfo=None) - at).total_seconds()), 5)

    def test_queued_time_is_kept(self):
        when = (datetime.now(timezone.utc) - timedelta(hours=3)).replace(microsecond=0)
        at, offline = client_time({'at': when.isoformat()})
        self.assertTrue(offline)
        self.assertEqual(at, when.replace(tzinfo=None))

    def test_future_is_clamped_and_old_refused(self):
        future = datetime.now(timezone.utc) + timedelta(days=2)
        at, _offline = client_time({'at': future.isoformat()})
        self.assertLessEqual(at, datetime.now(timezone.utc).replace(tzinfo=None))
        with self.assertRaises(ValueError):
            client_time({'at': (datetime.now(timezone.utc) - timedelta(days=30)).isoformat()})

    def test_clock_skew(self):
        self.assertIsNone(clock_skew_minutes({}))
        late = datetime.now(timezone.utc) - timedelta(minutes=42)
        self.assertAlmostEqual(clock_skew_minutes({'device_time': late.isoformat()}), 42, delta=1)

    def test_field_timezone_fallback(self):
        employee = self.env['hr.employee'].create({'name': 'UTC Officer', 'tz': 'UTC'})
        self.env['ir.config_parameter'].sudo().set_param('ff_base.default_tz', 'Asia/Kolkata')
        self.assertEqual(employee._ff_tz().zone, 'Asia/Kolkata')
        employee.tz = 'Europe/London'
        self.assertEqual(employee._ff_tz().zone, 'Europe/London')
