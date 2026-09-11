from odoo.exceptions import UserError
from odoo.tests import TransactionCase, tagged


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
            'partner_latitude': 10.0, 'partner_longitude': 76.0,
        })
        cls.new_shop = cls.env['res.partner'].create({
            'name': 'New Shop', 'ff_is_client': True, 'ff_category_id': category.id,
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

        far = self.Visit.ff_check_in(self.employee, self.shop, {'lat': 10.01, 'lng': 76.0})
        self.assertFalse(far.inside_geofence)
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
