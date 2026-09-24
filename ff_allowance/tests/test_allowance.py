from odoo import fields
from odoo.tests import TransactionCase, tagged


@tagged('post_install', '-at_install', 'ff')
class TestAllowance(TransactionCase):

    @classmethod
    def setUpClass(cls):
        super().setUpClass()
        cls.department = cls.env['hr.department'].create({'name': 'Field Sales'})
        cls.employee = cls.env['hr.employee'].create({
            'name': 'Allowance Officer', 'tz': 'UTC', 'department_id': cls.department.id,
        })
        category = cls.env.ref('ff_clients.contact_category_customer')
        Partner = cls.env['res.partner']
        vals = {'ff_is_client': True, 'ff_category_id': category.id, 'ff_employee_ids': [(6, 0, cls.employee.ids)]}
        cls.c1 = Partner.create(dict(vals, name='A', partner_latitude=10.0, partner_longitude=76.0))
        cls.c2 = Partner.create(dict(vals, name='B', partner_latitude=10.009, partner_longitude=76.0))
        beat_type = cls.env.ref('ff_beat.route_type_beat')
        cls.route1 = cls.env['ff.beat'].create({'name': 'R1', 'route_type_id': beat_type.id, 'allowance_km': 10,
                                                'line_ids': [(0, 0, {'partner_id': cls.c1.id})]})
        cls.route2 = cls.env['ff.beat'].create({'name': 'R2', 'route_type_id': beat_type.id, 'allowance_km': 5,
                                                'line_ids': [(0, 0, {'partner_id': cls.c2.id})]})
        cls.employee.ff_route_ids = cls.route1 | cls.route2
        cls.Policy = cls.env['ff.allowance.policy']
        cls.today = fields.Date.context_today(cls.employee)

    def _visit_both(self):
        Visit = self.env['ff.visit']
        Visit.ff_check_in(self.employee, self.c1, {'lat': 10.0, 'lng': 76.0}).ff_check_out({})
        Visit.ff_check_in(self.employee, self.c2, {'lat': 10.009, 'lng': 76.0}).ff_check_out({})

    def test_policy_resolution(self):
        default = self.Policy.create({'name': 'Default', 'basis': 'gps', 'rate_per_km': 3})
        self.assertEqual(self.Policy._ff_for_employee(self.employee), default)
        dept = self.Policy.create({'name': 'Dept', 'basis': 'gps', 'rate_per_km': 4,
                                   'department_ids': [(6, 0, self.department.ids)]})
        self.assertEqual(self.Policy._ff_for_employee(self.employee), dept)
        personal = self.Policy.create({'name': 'Personal', 'basis': 'fixed', 'fixed_amount': 200})
        self.employee.ff_allowance_policy_id = personal
        self.assertEqual(self.Policy._ff_for_employee(self.employee), personal)

    def test_client_to_client(self):
        self.Policy.create({'name': 'Client km', 'basis': 'client', 'rate_per_km': 5, 'road_factor': 1.3})
        self._visit_both()
        claim = self.env['ff.allowance.claim']._ff_compute(self.employee, self.today)
        self.assertAlmostEqual(claim.distance_km, 1.3, delta=0.05)  # ~1 km straight x 1.3
        self.assertAlmostEqual(claim.amount, claim.distance_km * 5, delta=0.01)
        self.assertTrue(claim.estimated)

    def test_route_to_route_with_agreed_distance(self):
        self.Policy.create({'name': 'Route km', 'basis': 'route', 'rate_per_km': 4})
        self.env['ff.route.distance'].create({'from_beat_id': self.route2.id, 'to_beat_id': self.route1.id,
                                              'distance_km': 12})
        self._visit_both()
        claim = self.env['ff.allowance.claim']._ff_compute(self.employee, self.today)
        # 10 (working R1) + 12 (R1 -> R2, agreed in reverse direction) + 5 (working R2)
        self.assertAlmostEqual(claim.distance_km, 27.0)
        self.assertAlmostEqual(claim.amount, 108.0)
        self.assertFalse(claim.estimated)

    def test_max_km_and_locked_after_submit(self):
        self.Policy.create({'name': 'Capped', 'basis': 'route', 'rate_per_km': 4, 'max_km_per_day': 20})
        self._visit_both()
        Claim = self.env['ff.allowance.claim']
        claim = Claim._ff_compute(self.employee, self.today)
        self.assertAlmostEqual(claim.distance_km, 20.0)
        claim.action_submit()
        self.env['ff.route.distance'].create({'from_beat_id': self.route1.id, 'to_beat_id': self.route2.id,
                                              'distance_km': 1})
        self.assertAlmostEqual(Claim._ff_compute(self.employee, self.today).distance_km, 20.0)
