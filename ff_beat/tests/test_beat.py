from datetime import date, timedelta

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
        vals = {'ff_is_client': True, 'ff_category_id': category.id, 'ff_employee_ids': [(6, 0, cls.employee.ids)]}
        cls.c1 = Partner.create(dict(vals, name='C1', partner_latitude=10.0, partner_longitude=76.0))
        cls.c2 = Partner.create(dict(vals, name='C2', partner_latitude=10.009, partner_longitude=76.0))
        cls.c3 = Partner.create(dict(vals, name='C3', partner_latitude=10.5, partner_longitude=76.0))
        cls.beat_type = cls.env.ref('ff_beat.route_type_beat')
        cls.patch_type = cls.env['ff.route.type'].create({'name': 'Patch', 'department_ids': [(6, 0, cls.medical.ids)]})
        cls.beat = cls.env['ff.beat'].create({
            'name': 'Test Beat', 'route_type_id': cls.beat_type.id,
            'line_ids': [(0, 0, {'partner_id': cls.c1.id, 'sequence': 1}),
                         (0, 0, {'partner_id': cls.c2.id, 'sequence': 2})],
        })
        cls.beat2 = cls.env['ff.beat'].create({
            'name': 'Second Beat', 'route_type_id': cls.beat_type.id,
            'line_ids': [(0, 0, {'partner_id': cls.c3.id, 'sequence': 1})],
        })
        cls.employee.ff_route_ids = cls.beat | cls.beat2
        cls.Day = cls.env['ff.beat.plan']
        cls.today = fields.Date.context_today(cls.employee)

    def test_route_label_per_department(self):
        self.assertEqual(self.employee._ff_route_label(), 'Beat')
        rep = self.env['hr.employee'].create({'name': 'Rep', 'department_id': self.medical.id})
        self.assertEqual(rep._ff_route_label(), 'Patch')

    def test_day_plan_customers_status_and_monthly_totals(self):
        day = self.Day.create({'employee_id': self.employee.id, 'beat_id': self.beat.id, 'date': self.today})
        self.assertEqual(day.plan_id.month, self.today.replace(day=1))
        self.assertEqual(day.customer_line_ids.partner_id, self.c1 | self.c2)
        day.customer_line_ids.filtered(lambda l: l.partner_id == self.c2).selected = False  # untick C2
        self.assertEqual(day.planned_count, 1)

        Visit = self.env['ff.visit']
        visit = Visit.ff_check_in(self.employee, self.c1, {'lat': 10.0, 'lng': 76.0})
        visit.ff_check_out({})
        line1 = day.customer_line_ids.filtered(lambda l: l.partner_id == self.c1)
        self.assertEqual(visit.beat_plan_id, day)
        self.assertTrue(visit.is_planned)
        self.assertEqual(line1.status, 'visited')
        Visit.ff_check_in(self.employee, self.c3, {'lat': 10.5, 'lng': 76.0}).ff_check_out({})
        self.assertEqual(day.adhoc_count, 1)
        self.assertEqual((day.plan_id.visited_count, day.plan_id.planned_count), (1, 1))
        self.assertAlmostEqual(day.plan_id.completion_pct, 100.0)

    def test_missed_and_cancelled(self):
        past = self.today - timedelta(days=3)
        day = self.Day.create({'employee_id': self.employee.id, 'beat_id': self.beat.id, 'date': past})
        self.assertEqual(set(day.customer_line_ids.mapped('status')), {'missed'})
        day.customer_line_ids[:1].cancelled = True
        self.assertEqual(day.customer_line_ids[:1].status, 'cancelled')
        self.assertEqual((day.missed_count, day.cancelled_count), (1, 1))

    def test_routes_per_day_setting(self):
        self.Day.create({'employee_id': self.employee.id, 'beat_id': self.beat.id, 'date': date(2026, 3, 2)})
        with self.assertRaises(ValidationError):
            self.Day.create({'employee_id': self.employee.id, 'beat_id': self.beat2.id, 'date': date(2026, 3, 2)})
        self.employee.ff_routes_per_day = 'multiple'
        self.Day.create({'employee_id': self.employee.id, 'beat_id': self.beat2.id, 'date': date(2026, 3, 2)})

    def test_plan_requires_assigned_route(self):
        other = self.env['ff.beat'].create({'name': 'Other', 'route_type_id': self.patch_type.id})
        with self.assertRaises(ValidationError):
            self.Day.create({'employee_id': self.employee.id, 'beat_id': other.id, 'date': date(2026, 2, 2)})

    def test_template_and_copy_previous_month(self):
        template = self.env['ff.route.plan.template'].create({
            'name': 'Mondays', 'line_ids': [(0, 0, {'weekday': '0', 'week': 'all', 'beat_id': self.beat.id})],
        })
        self.env['ff.route.plan.apply.wizard'].create({
            'template_id': template.id, 'employee_ids': [(6, 0, self.employee.ids)],
            'date_from': date(2026, 1, 1), 'date_to': date(2026, 1, 31),
        }).action_apply()
        january = self.env['ff.route.plan'].search([('employee_id', '=', self.employee.id), ('month', '=', date(2026, 1, 1))])
        self.assertEqual(january.name, 'Beat Officer - January 2026 Plan')
        self.assertEqual(sorted(january.day_ids.mapped('date')),
                         [date(2026, 1, 5), date(2026, 1, 12), date(2026, 1, 19), date(2026, 1, 26)])

        february = self.env['ff.route.plan']._ff_get(self.employee, date(2026, 2, 1))
        february.action_copy_previous_month()
        self.assertEqual(sorted(february.day_ids.mapped('date')),
                         [date(2026, 2, 2), date(2026, 2, 9), date(2026, 2, 16), date(2026, 2, 23)])

    def test_contact_gets_route_employees(self):
        rep2 = self.env['hr.employee'].create({'name': 'Second Rep'})
        self.beat.employee_ids = self.employee | rep2
        contact = self.env['res.partner'].create({
            'name': 'New Outlet', 'ff_is_client': True,
            'ff_category_id': self.env.ref('ff_clients.contact_category_customer').id,
            'ff_employee_ids': [(6, 0, self.employee.ids)],
            'ff_route_ids': [(4, self.beat.id)],
        })
        self.assertIn(self.beat, contact.ff_route_ids)
        self.assertEqual(contact.ff_employee_ids, self.employee | rep2)
