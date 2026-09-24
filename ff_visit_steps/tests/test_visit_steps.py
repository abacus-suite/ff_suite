from odoo.exceptions import UserError
from odoo.tests import TransactionCase, tagged


@tagged('post_install', '-at_install', 'ff')
class TestVisitSteps(TransactionCase):

    @classmethod
    def setUpClass(cls):
        super().setUpClass()
        cls.env['ir.config_parameter'].sudo().set_param('ff_base.visit_steps', 'True')
        cls.env['ir.config_parameter'].sudo().set_param('ff_base.stock_count', 'True')
        cls.employee = cls.env['hr.employee'].create({'name': 'Steps Officer', 'tz': 'UTC'})
        cls.shop = cls.env['res.partner'].create({
            'name': 'Steps Shop', 'ff_is_client': True,
            'ff_category_id': cls.env.ref('ff_clients.contact_category_customer').id,
            'ff_employee_ids': [(6, 0, cls.employee.ids)],
            'partner_latitude': 10.0, 'partner_longitude': 76.0,
        })
        cls.product = cls.env['product.product'].create({'name': 'Lychee Rose', 'sale_ok': True})
        cls.notes_step = cls.env.ref('ff_visit_steps.visit_step_notes')
        cls.stock_step = cls.env.ref('ff_visit_steps.visit_step_stock')
        cls.Visit = cls.env['ff.visit']
        cls.Record = cls.env['ff.visit.step.record']

    def test_mandatory_step_blocks_checkout(self):
        visit = self.Visit.ff_check_in(self.employee, self.shop, {'lat': 10.0, 'lng': 76.0})
        with self.assertRaises(UserError):
            visit.ff_check_out({})
        with self.assertRaises(UserError):  # notes step cannot be empty
            self.Record.ff_complete(self.employee, visit, self.notes_step, {})
        with self.assertRaises(UserError):  # and it cannot be skipped
            self.Record.ff_complete(self.employee, visit, self.notes_step, {'skip': True, 'skip_reason': 'busy'})
        record = self.Record.ff_complete(self.employee, visit, self.notes_step,
                                         {'note': 'Owner not available, will come back Friday'})
        self.assertEqual(record.state, 'done')
        visit.ff_check_out({})
        self.assertEqual(visit.state, 'done')

    def test_stock_count_keeps_previous_count(self):
        first = self.Visit.ff_check_in(self.employee, self.shop, {'lat': 10.0, 'lng': 76.0})
        self.Record.ff_complete(self.employee, first, self.stock_step,
                                {'lines': [{'product_id': self.product.id, 'quantity': 12}]})
        self.Record.ff_complete(self.employee, first, self.notes_step, {'note': 'First count'})
        first.ff_check_out({})

        second = self.Visit.ff_check_in(self.employee, self.shop, {'lat': 10.0, 'lng': 76.0})
        record = self.Record.ff_complete(self.employee, second, self.stock_step,
                                         {'lines': [{'product_id': self.product.id, 'quantity': 5}]})
        line = record.stock_count_id.line_ids
        self.assertEqual(line.previous_quantity, 12)
        self.assertTrue(line.previous_date)
        self.assertEqual(line.delta, -7)

    def test_optional_step_can_be_skipped_with_reason(self):
        visit = self.Visit.ff_check_in(self.employee, self.shop, {'lat': 10.0, 'lng': 76.0})
        record = self.Record.ff_complete(self.employee, visit, self.stock_step,
                                         {'skip': True, 'skip_reason': 'Shop closed for lunch'})
        self.assertEqual(record.state, 'skipped')
        self.assertEqual(record.skip_reason, 'Shop closed for lunch')
