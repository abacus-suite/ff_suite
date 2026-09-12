from odoo.tests import TransactionCase, tagged


@tagged('post_install', '-at_install', 'ff')
class TestAttribution(TransactionCase):

    @classmethod
    def setUpClass(cls):
        super().setUpClass()
        cls.employee = cls.env['hr.employee'].create({'name': 'Route Seller'})
        cls.route = cls.env['ff.beat'].create({
            'name': 'Attribution Route',
            'route_type_id': cls.env['ff.route.type'].create({'name': 'Beat'}).id,
            'employee_ids': [(6, 0, cls.employee.ids)],
        })
        cls.district = cls.env['ff.district'].create({
            'name': 'Attribution City',
            'state_id': cls.env['res.country.state'].search([], limit=1).id,
        })
        cls.shop = cls.env['res.partner'].create({
            'name': 'Attribution Shop', 'ff_is_client': True,
            'ff_employee_ids': [(6, 0, cls.employee.ids)],
            'ff_district_id': cls.district.id,
            'ff_route_ids': [(6, 0, cls.route.ids)],
        })

    def test_partner_carries_its_main_employee_and_route(self):
        self.assertEqual(self.shop.ff_primary_employee_id, self.employee)
        self.assertEqual(self.shop.ff_primary_route_id, self.route)

    def test_back_office_order_is_credited_from_the_contact(self):
        order = self.env['sale.order'].create({'partner_id': self.shop.id})
        self.assertEqual(order.ff_employee_id, self.employee)
        self.assertEqual(order.ff_route_id, self.route)
        self.assertEqual(order.ff_district_id, self.district)
        self.assertEqual(order.ff_team_id, self.employee.ff_team_id)

    def test_a_chosen_employee_is_never_overwritten(self):
        other = self.env['hr.employee'].create({'name': 'Desk Seller'})
        order = self.env['sale.order'].create({'partner_id': self.shop.id, 'ff_employee_id': other.id})
        self.assertEqual(order.ff_employee_id, other)
