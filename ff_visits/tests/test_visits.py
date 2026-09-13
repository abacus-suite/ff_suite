from odoo.exceptions import UserError
from odoo.tests import TransactionCase, tagged

from odoo.addons.ff_visits.models.ff_visit import OffsiteConfirmation


@tagged('post_install', '-at_install', 'ff')
class TestVisits(TransactionCase):

    @classmethod
    def setUpClass(cls):
        super().setUpClass()
        cls.env['ir.config_parameter'].sudo().set_param('ff_base.geofence_radius', '150')
        cls.employee = cls.env['hr.employee'].create({'name': 'Visit Officer', 'tz': 'UTC'})
        category = cls.env.ref('ff_clients.contact_category_customer')
        cls.shop = cls.env['res.partner'].create({
            'name': 'Anand Stores', 'ff_is_client': True, 'ff_category_id': category.id,
            'ff_employee_ids': [(6, 0, cls.employee.ids)],
            'partner_latitude': 10.0, 'partner_longitude': 76.0,
        })
        cls.new_shop = cls.env['res.partner'].create({
            'name': 'New Shop', 'ff_is_client': True, 'ff_category_id': category.id,
            'ff_employee_ids': [(6, 0, cls.employee.ids)],
        })
        cls.Visit = cls.env['ff.visit']

    def test_check_in_inside_and_outside(self):
        visit = self.Visit.ff_check_in(self.employee, self.shop, {'lat': 10.0005, 'lng': 76.0, 'uuid': 'v-in'})
        self.assertTrue(visit.inside_geofence)
        self.assertLess(visit.distance_m, 150)
        self.assertEqual(self.Visit.ff_check_in(self.employee, self.shop, {'lat': 10.0, 'lng': 76.0, 'uuid': 'v-in'}), visit)
        visit.ff_check_out({'outcome': 'met', 'photos': ['iVBORw0KGgo=']})
        self.assertEqual(visit.state, 'done')
        self.assertEqual(visit.photo_count, 1)

        with self.assertRaises(OffsiteConfirmation):
            self.Visit.ff_check_in(self.employee, self.shop, {'lat': 10.01, 'lng': 76.0})
        far = self.Visit.ff_check_in(self.employee, self.shop, {'lat': 10.01, 'lng': 76.0, 'offsite': True})
        self.assertFalse(far.inside_geofence)
        self.assertEqual(far.visit_type, 'offsite')
        far.ff_check_out({})

        self.env['ir.config_parameter'].sudo().set_param('ff_base.visit_block_outside', 'True')
        with self.assertRaises(UserError):
            self.Visit.ff_check_in(self.employee, self.shop, {'lat': 10.01, 'lng': 76.0})

    def test_location_captured_and_single_ongoing(self):
        visit = self.Visit.ff_check_in(self.employee, self.new_shop, {'lat': 11.0, 'lng': 77.0})
        self.assertTrue(visit.location_captured)
        self.assertAlmostEqual(self.new_shop.partner_latitude, 11.0)
        with self.assertRaises(UserError):
            self.Visit.ff_check_in(self.employee, self.shop, {'lat': 10.0, 'lng': 76.0})
        visit.ff_check_out({})
        self.assertTrue(self.Visit.ff_check_in(self.employee, self.shop, {'lat': 10.0, 'lng': 76.0}))
        self.assertTrue(self.shop.ff_last_visit_at)

    def test_mock_blocked(self):
        with self.assertRaises(UserError):
            self.Visit.ff_check_in(self.employee, self.shop, {'lat': 10.0, 'lng': 76.0, 'mock': True})

    def test_outcome_rules(self):
        other = self.env.ref('ff_visits.visit_outcome_other')  # note required
        closed = self.env.ref('ff_visits.visit_outcome_closed')  # photo required, not productive
        visit = self.Visit.ff_check_in(self.employee, self.shop, {'lat': 10.0, 'lng': 76.0})
        with self.assertRaises(UserError):
            visit.ff_check_out({'outcome_id': other.id})
        with self.assertRaises(UserError):
            visit.ff_check_out({'outcome': 'closed'})  # legacy code still validated
        visit.ff_check_out({'outcome_id': closed.id, 'photos': ['iVBORw0KGgo=']})
        self.assertEqual(visit.outcome_id, closed)
        self.assertEqual(visit.outcome, 'closed')
        self.assertFalse(visit.productive)

    def test_offline_check_in_keeps_real_time_and_is_offsite_when_far(self):
        at = '2020-01-01T00:00:00Z'
        with self.assertRaises(UserError):  # older than the offline window
            self.Visit.ff_check_in(self.employee, self.shop, {'lat': 10.01, 'lng': 76.0, 'at': at})
        from datetime import datetime, timedelta, timezone
        recent = (datetime.now(timezone.utc) - timedelta(hours=2)).replace(microsecond=0)
        visit = self.Visit.ff_check_in(self.employee, self.shop, {
            'lat': 10.01, 'lng': 76.0, 'uuid': 'offline-1', 'at': recent.isoformat()})
        self.assertTrue(visit.ff_offline)
        self.assertEqual(visit.visit_type, 'offsite')
        self.assertEqual(visit.check_in_at, recent.replace(tzinfo=None))
        self.assertTrue(visit.offsite_reason)
        visit.ff_check_out({'at': (recent + timedelta(minutes=20)).isoformat()})
        self.assertEqual(visit.duration_min, 20)

    def test_require_visit(self):
        with self.assertRaises(UserError):
            self.Visit.ff_require_visit(self.employee, self.shop)
        visit = self.Visit.ff_check_in(self.employee, self.shop, {'lat': 10.0, 'lng': 76.0})
        self.assertEqual(self.Visit.ff_require_visit(self.employee, self.shop), visit)
        with self.assertRaises(UserError):
            self.Visit.ff_require_visit(self.employee, self.new_shop)
        visit.ff_check_out({})
        # Checked out, but visited today: an order queued offline still syncs.
        self.assertEqual(self.Visit.ff_require_visit(self.employee, self.shop), visit)
