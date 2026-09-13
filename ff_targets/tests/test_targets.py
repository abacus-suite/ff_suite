from odoo.exceptions import ValidationError
from odoo.tests import TransactionCase, tagged


@tagged('post_install', '-at_install', 'ff')
class TestTargets(TransactionCase):

    @classmethod
    def setUpClass(cls):
        super().setUpClass()
        cls.employee = cls.env['hr.employee'].create({'name': 'Target Officer', 'tz': 'Asia/Kolkata'})
        category = cls.env.ref('ff_clients.contact_category_customer')
        cls.shop = cls.env['res.partner'].create({
            'name': 'Target Stores', 'ff_is_client': True, 'ff_category_id': category.id,
            'ff_employee_ids': [(6, 0, cls.employee.ids)], 'partner_latitude': 10.0, 'partner_longitude': 76.0,
        })

    def test_month_is_normalised_and_unique(self):
        today = self.employee._ff_today()
        target = self.env['ff.target'].create({'employee_id': self.employee.id, 'month': today, 'visit_target': 4})
        self.assertEqual(target.month.day, 1)
        with self.assertRaises(Exception):
            with self.env.cr.savepoint():
                self.env['ff.target'].create({'employee_id': self.employee.id, 'month': today})
        with self.assertRaises(ValidationError):
            target.visit_target = -1

    def test_achievement_counts_visits(self):
        today = self.employee._ff_today()
        target = self.env['ff.target'].create({
            'employee_id': self.employee.id, 'month': today, 'visit_target': 4, 'customer_target': 0})
        visit = self.env['ff.visit'].ff_check_in(self.employee, self.shop, {'lat': 10.0, 'lng': 76.0})
        visit.ff_check_out({})
        self.env['ff.visit'].ff_check_in(self.employee, self.shop, {'lat': 10.0, 'lng': 76.0})
        target.invalidate_recordset()
        self.assertEqual(target.visit_actual, 2)
        self.assertEqual(target.achievement, 50)
        progress = self.env['ff.target'].ff_progress(self.employee, today)
        self.assertEqual(progress['rows'][0]['achievement'], 50)

    def test_copy_to_next_month(self):
        today = self.employee._ff_today()
        target = self.env['ff.target'].create({'employee_id': self.employee.id, 'month': today, 'visit_target': 10})
        target.action_copy_to_next_month()
        target.action_copy_to_next_month()  # already there: not copied twice
        self.assertEqual(self.env['ff.target'].search_count([('employee_id', '=', self.employee.id)]), 2)
