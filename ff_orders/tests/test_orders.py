from odoo.exceptions import UserError
from odoo.tests import TransactionCase, tagged


@tagged('post_install', '-at_install', 'ff')
class TestFieldOrders(TransactionCase):

    @classmethod
    def setUpClass(cls):
        super().setUpClass()
        cls.employee = cls.env['hr.employee'].create({'name': 'Order Officer', 'tz': 'UTC'})
        cls.client = cls.env['res.partner'].create({
            'name': 'Order Client', 'ff_is_client': True, 'partner_latitude': 10.0, 'partner_longitude': 76.0,
            'ff_category_id': cls.env.ref('ff_clients.contact_category_customer').id,
            'ff_employee_ids': [(6, 0, cls.employee.ids)],
        })
        cls.product = cls.env['product.product'].create({
            'name': 'Lychee Rose', 'list_price': 100.0, 'sale_ok': True, 'ff_sku_code': 'LR',
        })
        cls.hidden = cls.env['product.product'].create({'name': 'Hidden', 'sale_ok': True, 'ff_show_in_app': False})
        cls.Order = cls.env['sale.order']

    def test_create_order_linked_to_visit(self):
        visit = self.env['ff.visit'].ff_check_in(self.employee, self.client, {'lat': 10.0, 'lng': 76.0})
        data = {'uuid': 'ord-1', 'lines': [{'product_id': self.product.id, 'qty': 3}], 'note': 'Urgent'}
        order = self.Order.ff_create_from_app(self.employee, self.client, data)
        self.assertEqual(order.ff_source, 'app')
        self.assertEqual(order.ff_visit_id, visit)
        self.assertEqual(visit.outcome, 'order')
        self.assertEqual(order.order_line.product_uom_qty, 3)
        self.assertAlmostEqual(order.amount_untaxed, 300.0)
        self.assertEqual(self.Order.ff_create_from_app(self.employee, self.client, data), order)

    def test_invalid_orders_rejected(self):
        with self.assertRaises(UserError):
            self.Order.ff_create_from_app(self.employee, self.client, {'lines': []})
        with self.assertRaises(UserError):
            self.Order.ff_create_from_app(self.employee, self.client,
                                          {'lines': [{'product_id': self.hidden.id, 'qty': 1}]})
        self.client.ff_category_id = self.env.ref('ff_clients.contact_category_lead')  # leads: no orders
        with self.assertRaises(UserError):
            self.Order.ff_create_from_app(self.employee, self.client,
                                          {'lines': [{'product_id': self.product.id, 'qty': 1}]})
        self.client.ff_category_id = self.env.ref('ff_clients.contact_category_customer')
        self.client.ff_approval_state = 'pending'
        with self.assertRaises(UserError):
            self.Order.ff_create_from_app(self.employee, self.client,
                                          {'lines': [{'product_id': self.product.id, 'qty': 1}]})
