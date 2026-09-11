from datetime import date

from odoo import fields
from odoo.tests import TransactionCase, tagged


@tagged('post_install', '-at_install', 'ff')
class TestBeat(TransactionCase):

    @classmethod
    def setUpClass(cls):
        super().setUpClass()
        cls.employee = cls.env['hr.employee'].create({'name': 'Beat Officer', 'tz': 'UTC'})
        Partner = cls.env['res.partner']
        cls.c1 = Partner.create({'name': 'C1', 'ff_is_client': True, 'partner_latitude': 10.0, 'partner_longitude': 76.0})
        cls.c2 = Partner.create({'name': 'C2', 'ff_is_client': True, 'partner_latitude': 10.009, 'partner_longitude': 76.0})
        cls.c3 = Partner.create({'name': 'C3', 'ff_is_client': True, 'partner_latitude': 10.5, 'partner_longitude': 76.0})
        cls.beat = cls.env['ff.beat'].create({
            'name': 'Test Beat',
            'line_ids': [(0, 0, {'partner_id': cls.c1.id, 'sequence': 1}),
                         (0, 0, {'partner_id': cls.c2.id, 'sequence': 2})],
        })

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
        adhoc = Visit.ff_check_in(self.employee, self.c3, {'lat': 10.5, 'lng': 76.0})
        adhoc.ff_check_out({})

        self.assertEqual((plan.planned_count, plan.completed_count, plan.adhoc_count), (2, 1, 1))
        self.assertAlmostEqual(plan.completion_pct, 50.0)
        self.assertEqual(plan.status, 'in_progress')

    def test_assign_wizard_skips_sunday(self):
        wizard = self.env['ff.beat.assign.wizard'].create({
            'beat_id': self.beat.id,
            'employee_ids': [(6, 0, self.employee.ids)],
            'date_from': date(2026, 1, 5),   # Monday
            'date_to': date(2026, 1, 11),    # Sunday
        })
        wizard.action_assign()
        plans = self.env['ff.beat.plan'].search([('employee_id', '=', self.employee.id)])
        self.assertEqual(len(plans), 6)
        wizard.action_assign()  # idempotent
        self.assertEqual(self.env['ff.beat.plan'].search_count([('employee_id', '=', self.employee.id)]), 6)
