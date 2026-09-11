from datetime import date

from odoo import fields
from odoo.exceptions import ValidationError
from odoo.tests import TransactionCase, tagged


@tagged('post_install', '-at_install', 'ff')
class TestBeat(TransactionCase):

    @classmethod
    def setUpClass(cls):
        super().setUpClass()
        cls.sales = cls.env['hr.department'].create({'name': 'Sales'})
        cls.medical = cls.env['hr.department'].create({'name': 'Medical'})
        cls.employee = cls.env['hr.employee'].create({'name': 'Beat Officer', 'tz': 'UTC', 'department_id': cls.sales.id})
        category = cls.env.ref('ff_clients.contact_category_customer')
        Partner = cls.env['res.partner']
        vals = {'ff_is_client': True, 'ff_category_id': category.id}
        cls.c1 = Partner.create(dict(vals, name='C1', partner_latitude=10.0, partner_longitude=76.0))
        cls.c2 = Partner.create(dict(vals, name='C2', partner_latitude=10.009, partner_longitude=76.0))
        cls.c3 = Partner.create(dict(vals, name='C3', partner_latitude=10.5, partner_longitude=76.0))
        cls.patch_type = cls.env['ff.route.type'].create({'name': 'Patch', 'department_ids': [(6, 0, cls.medical.ids)]})
        cls.beat = cls.env['ff.beat'].create({
            'name': 'Test Beat',
            'route_type_id': cls.env.ref('ff_beat.route_type_beat').id,
            'line_ids': [(0, 0, {'partner_id': cls.c1.id, 'sequence': 1}),
                         (0, 0, {'partner_id': cls.c2.id, 'sequence': 2})],
        })

    def test_route_label_per_department(self):
        self.assertEqual(self.employee._ff_route_label(), 'Beat')
        doctor_rep = self.env['hr.employee'].create({'name': 'Rep', 'department_id': self.medical.id})
        self.assertEqual(doctor_rep._ff_route_label(), 'Patch')

    def test_route_and_plan_stats(self):
        self.assertEqual(self.beat.client_count, 2)
        self.assertAlmostEqual(self.beat.planned_km, 1.0, delta=0.05)
        plan = self.env['ff.beat.plan'].create({
            'employee_id': self.employee.id, 'beat_id': self.beat.id,
            'date': fields.Date.context_today(self.employee),
        })
        Visit = self.env['ff.visit']
        visit = Visit.ff_check_in(self.employee, self.c1, {'lat': 10.0, 'lng': 76.0})
        self.assertEqual(visit.beat_plan_id, plan)
        self.assertTrue(visit.is_planned)
        visit.ff_check_out({'outcome': 'order'})
        Visit.ff_check_in(self.employee, self.c3, {'lat': 10.5, 'lng': 76.0}).ff_check_out({})
        self.assertEqual((plan.planned_count, plan.completed_count, plan.adhoc_count), (2, 1, 1))
        self.assertAlmostEqual(plan.completion_pct, 50.0)

    def test_plan_requires_assigned_route(self):
        other = self.env['ff.beat'].create({'name': 'Other', 'route_type_id': self.patch_type.id})
        self.employee.ff_route_ids = self.beat
        with self.assertRaises(ValidationError):
            self.env['ff.beat.plan'].create({'employee_id': self.employee.id, 'beat_id': other.id, 'date': date(2026, 2, 2)})

    def test_assign_wizard_skips_sunday_and_assigns_route(self):
        wizard = self.env['ff.beat.assign.wizard'].create({
            'beat_id': self.beat.id,
            'employee_ids': [(6, 0, self.employee.ids)],
            'date_from': date(2026, 1, 5),   # Monday
            'date_to': date(2026, 1, 11),    # Sunday
        })
        wizard.action_assign()
        self.assertIn(self.beat, self.employee.ff_route_ids)
        self.assertEqual(self.env['ff.beat.plan'].search_count([('employee_id', '=', self.employee.id)]), 6)
        wizard.action_assign()  # idempotent
        self.assertEqual(self.env['ff.beat.plan'].search_count([('employee_id', '=', self.employee.id)]), 6)
