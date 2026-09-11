from odoo.exceptions import UserError, ValidationError
from odoo.tests import TransactionCase, tagged


@tagged('post_install', '-at_install', 'ff')
class TestForms(TransactionCase):

    @classmethod
    def setUpClass(cls):
        super().setUpClass()
        cls.sales = cls.env['hr.department'].create({'name': 'Sales'})
        cls.employee = cls.env['hr.employee'].create({'name': 'Form Officer', 'tz': 'UTC', 'department_id': cls.sales.id})
        cls.outlet = cls.env.ref('ff_clients.contact_category_outlet')
        cls.shop = cls.env['res.partner'].create({
            'name': 'Audit Shop', 'ff_is_client': True, 'ff_category_id': cls.outlet.id,
            'partner_latitude': 10.0, 'partner_longitude': 76.0,
        })
        cls.form = cls.env['ff.form'].create({
            'name': 'Store Audit', 'trigger': 'visit', 'frequency': 'visit', 'mandatory': True,
            'category_ids': [(6, 0, cls.outlet.ids)],
            'field_ids': [
                (0, 0, {'name': 'Shop size', 'field_type': 'select', 'required': True, 'options': 'Small\nMedium\nLarge', 'sequence': 1}),
                (0, 0, {'name': 'Stock available', 'field_type': 'checkbox', 'required': True, 'sequence': 2}),
                (0, 0, {'name': 'Facings', 'field_type': 'number', 'min_value': 1, 'max_value': 50, 'sequence': 3}),
                (0, 0, {'name': 'Shelf photo', 'field_type': 'photo', 'sequence': 5}),
            ],
        })
        stock = cls.form.field_ids.filtered(lambda q: q.key == 'stock_available')
        cls.env['ff.form.field'].create({
            'form_id': cls.form.id, 'name': 'Why no stock', 'field_type': 'textarea', 'required': True,
            'sequence': 4, 'visible_if_field_id': stock.id, 'visible_if_value': 'no',
        })

    def test_keys_and_validation(self):
        self.assertEqual(self.form.field_ids.sorted('sequence').mapped('key'),
                         ['shop_size', 'stock_available', 'facings', 'why_no_stock', 'shelf_photo'])
        with self.assertRaises(ValidationError):
            self.form._ff_validate({'shop_size': 'Huge', 'stock_available': True})
        with self.assertRaises(ValidationError):
            self.form._ff_validate({'shop_size': 'Small', 'stock_available': True, 'facings': 99})
        with self.assertRaises(ValidationError):  # conditional question becomes required
            self.form._ff_validate({'shop_size': 'Small', 'stock_available': False})
        cleaned = self.form._ff_validate({'shop_size': 'Small', 'stock_available': True, 'facings': '12',
                                          'why_no_stock': 'ignored when hidden'})
        self.assertEqual(cleaned, {'shop_size': 'Small', 'stock_available': True, 'facings': 12})

    def test_mandatory_visit_form_blocks_checkout(self):
        visit = self.env['ff.visit'].ff_check_in(self.employee, self.shop, {'lat': 10.0, 'lng': 76.0})
        with self.assertRaises(UserError):
            visit.ff_check_out({})
        Response = self.env['ff.form.response']
        response = Response.ff_submit(self.employee, self.form, {
            'partner_id': self.shop.id, 'uuid': 'resp-1',
            'answers': {'shop_size': 'Large', 'stock_available': 'no', 'why_no_stock': 'Supplier delay'},
            'photos': {'shelf_photo': ['iVBORw0KGgo=']},
        })
        self.assertEqual(response.visit_id, visit)
        self.assertEqual(len(response.answers['shelf_photo']), 1)
        self.assertIn('Supplier delay', response.line_ids.mapped('value_text'))
        self.assertEqual(Response.ff_submit(self.employee, self.form, {'uuid': 'resp-1'}), response)
        with self.assertRaises(ValidationError):  # once per visit
            Response.ff_submit(self.employee, self.form, {
                'partner_id': self.shop.id, 'answers': {'shop_size': 'Small', 'stock_available': True}})
        visit.ff_check_out({})
        self.assertEqual(visit.state, 'done')

    def test_form_applicability_by_category_and_department(self):
        customer = self.env['res.partner'].create({
            'name': 'Customer', 'ff_is_client': True,
            'ff_category_id': self.env.ref('ff_clients.contact_category_customer').id,
        })
        Form = self.env['ff.form']
        self.assertIn(self.form, Form._ff_applicable(self.employee, 'visit', self.shop))
        self.assertNotIn(self.form, Form._ff_applicable(self.employee, 'visit', customer))
        self.form.department_ids = self.env['hr.department'].create({'name': 'Medical'})
        self.assertNotIn(self.form, Form._ff_applicable(self.employee, 'visit', self.shop))

    def test_app_profile_features(self):
        medical = self.env['hr.department'].create({'name': 'Medical Reps'})
        rep = self.env['hr.employee'].create({'name': 'Rep', 'department_id': medical.id})
        self.env['ff.app.profile'].create({
            'name': 'Medical', 'department_ids': [(6, 0, medical.ids)],
            'feature_orders': False, 'label_client': 'Doctor',
        })
        payload = self.env['ff.app.profile'].ff_for_employee(rep).ff_payload()
        self.assertFalse(payload['features']['orders'])
        self.assertEqual(payload['labels']['client'], 'Doctor')
        default = self.env['ff.app.profile'].ff_for_employee(self.employee).ff_payload()
        self.assertTrue(default['features']['orders'])
