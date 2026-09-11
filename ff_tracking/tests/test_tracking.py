from datetime import datetime, timedelta

from odoo import fields
from odoo.tests import TransactionCase, tagged

from odoo.addons.ff_base.tools import haversine_m, parse_client_dt, path_distance_km, to_iso


@tagged('post_install', '-at_install', 'ff')
class TestTracking(TransactionCase):

    @classmethod
    def setUpClass(cls):
        super().setUpClass()
        cls.employee = cls.env['hr.employee'].create({'name': 'Tracking Officer', 'tz': 'Asia/Kolkata'})

    def test_haversine(self):
        self.assertAlmostEqual(haversine_m(0, 0, 1, 0) / 1000, 111.19, delta=0.1)

    def test_path_distance_filters_jitter_jumps_and_bad_accuracy(self):
        t0 = datetime(2026, 1, 1, 4, 0)
        points = [
            (t0, 10.0, 76.0, 10),
            (t0 + timedelta(minutes=1), 10.00005, 76.0, 10),   # ~5 m jitter: ignored
            (t0 + timedelta(minutes=2), 10.009, 76.0, 10),     # ~1 km: counted
            (t0 + timedelta(minutes=3), 11.0, 76.0, 10),       # 110 km in 1 min: rejected
            (t0 + timedelta(minutes=4), 10.018, 76.0, 500),    # inaccurate: rejected
            (t0 + timedelta(minutes=5), 10.018, 76.0, 10),     # ~1 km: counted
        ]
        self.assertAlmostEqual(path_distance_km(points), 2.0, delta=0.05)

    def test_parse_client_dt(self):
        self.assertEqual(parse_client_dt('2026-01-01T10:00:00+05:30'), datetime(2026, 1, 1, 4, 30))
        self.assertEqual(parse_client_dt('2026-01-01T04:30:00Z'), datetime(2026, 1, 1, 4, 30))
        self.assertEqual(parse_client_dt(1767225600000), datetime(2026, 1, 1, 0, 0))

    def test_ingest_is_idempotent_and_updates_status(self):
        Ping = self.env['ff.location.ping']
        now = fields.Datetime.now()
        pings = [
            {'uuid': 'trk-1', 'lat': 10.0, 'lng': 76.0, 'ts': to_iso(now - timedelta(minutes=2)), 'battery': 50},
            {'uuid': 'trk-2', 'lat': 10.01, 'lng': 76.0, 'ts': to_iso(now - timedelta(minutes=1)), 'battery': 15},
        ]
        self.assertEqual(Ping.ff_ingest(self.employee, pings)['accepted'], 2)

        again = Ping.ff_ingest(self.employee, pings)
        self.assertEqual((again['accepted'], again['duplicates']), (0, 2))

        bad = Ping.ff_ingest(self.employee, [{'uuid': 'trk-3', 'lat': 'x', 'lng': 76.0}, {'lat': 0, 'lng': 0}])
        self.assertEqual(bad['rejected'], 2)

        status = self.env['ff.employee.status'].search([('employee_id', '=', self.employee.id)])
        self.assertAlmostEqual(status.latitude, 10.01)
        self.assertEqual(status.battery, 15)
        self.assertTrue(status.is_low_battery)
        self.assertTrue(status.moved_at)

    def test_daily_track_and_compliance(self):
        today = self.employee._ff_today()
        start, _end = self.employee._ff_day_bounds(today)
        base = start + timedelta(hours=4)
        self.env['ff.location.ping'].ff_ingest(self.employee, [
            {'uuid': 'day-%s' % i, 'lat': 10.0 + 0.009 * i, 'lng': 76.0, 'accuracy': 10,
             'ts': to_iso(base + timedelta(minutes=5 * i))}
            for i in range(3)
        ])
        track = self.env['ff.daily.track']._ff_compute(self.employee, today)
        self.assertAlmostEqual(track.distance_km, 2.0, delta=0.05)
        self.assertEqual(track.ping_count, 3)

        res = self.env['ff.compliance.log'].ff_log(self.employee, [
            {'uuid': 'cmp-1', 'type': 'gps_off'},
            {'uuid': 'cmp-2', 'type': 'not_a_real_event'},
        ])
        self.assertEqual((res['accepted'], res['rejected']), (1, 1))
        status = self.env['ff.employee.status']._ff_get(self.employee)
        self.assertFalse(status.gps_on)
