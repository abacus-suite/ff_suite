from odoo.tests import TransactionCase, tagged


@tagged('post_install', '-at_install', 'ff')
class TestFoc(TransactionCase):

    @classmethod
    def setUpClass(cls):
        super().setUpClass()
        cls.employee = cls.env['hr.employee'].create({'name': 'FOC Rep', 'tz': 'UTC'})
        category = cls.env.ref('ff_clients.contact_category_customer')
        cls.shop = cls.env['res.partner'].create({
            'name': 'FOC Stores', 'ff_is_client': True, 'ff_category_id': category.id,
            'ff_employee_ids': [(6, 0, cls.employee.ids)]})
        cls.soap = cls.env['product.product'].create({'name': 'Soap', 'sale_ok': True, 'lst_price': 20})
        cls.shampoo = cls.env['product.product'].create({'name': 'Shampoo', 'sale_ok': True, 'lst_price': 90})
        cls.Scheme = cls.env['ff.foc.scheme']

    def test_slabs_repeat_and_other_product(self):
        slab = self.Scheme.create({'name': 'Slab', 'product_ids': [(6, 0, self.soap.ids)],
                                   'slab_ids': [(0, 0, {'min_qty': 10, 'free_qty': 1}), (0, 0, {'min_qty': 25, 'free_qty': 3})]})
        free = self.Scheme.ff_compute(self.employee, self.shop, [(self.soap, 26)])
        self.assertEqual(free[0]['quantity'], 3)
        slab.write({'slab_ids': [(5, 0, 0), (0, 0, {'min_qty': 10, 'free_qty': 1})], 'repeat': True,
                    'free_product_id': self.shampoo.id})
        free = self.Scheme.ff_compute(self.employee, self.shop, [(self.soap, 34), (self.shampoo, 50)])
        self.assertEqual(len(free), 1)
        self.assertEqual(free[0]['quantity'], 3)
        self.assertEqual(free[0]['product'], self.shampoo)
        self.assertFalse(self.Scheme.ff_compute(self.employee, self.shop, [(self.soap, 9)]))

    def test_combined(self):
        self.Scheme.create({'name': 'Combo', 'basis': 'combined', 'product_ids': [(6, 0, (self.soap | self.shampoo).ids)],
                            'slab_ids': [(0, 0, {'min_qty': 12, 'free_qty': 2})]})
        free = self.Scheme.ff_compute(self.employee, self.shop, [(self.soap, 6), (self.shampoo, 7)])
        self.assertEqual(free[0]['quantity'], 2)
