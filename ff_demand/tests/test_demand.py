from odoo.exceptions import UserError
from odoo.tests import TransactionCase, tagged


@tagged('post_install', '-at_install', 'ff')
class TestDemand(TransactionCase):
    """Demand collected at the counter, quoted to the distributor."""

    @classmethod
    def setUpClass(cls):
        super().setUpClass()
        cls.env['ir.config_parameter'].sudo().set_param('ff_base.order_flow', 'demand')
        cls.employee = cls.env['hr.employee'].create({'name': 'Demand Officer', 'tz': 'UTC'})
        cls.distributor = cls.env['res.partner'].create({
            'name': 'South Distributors', 'ff_is_distributor': True})
        category = cls.env.ref('ff_clients.contact_category_customer')
        vals = {'ff_is_client': True, 'ff_category_id': category.id,
                'ff_approval_state': 'approved', 'ff_employee_ids': [(6, 0, cls.employee.ids)]}
        cls.shop_a = cls.env['res.partner'].create(
            dict(vals, name='Shop A', ff_distributor_id=cls.distributor.id))
        cls.shop_b = cls.env['res.partner'].create(
            dict(vals, name='Shop B', ff_distributor_id=cls.distributor.id))
        cls.product = cls.env['product.product'].create({
            'name': 'Cardia 10mg', 'sale_ok': True, 'list_price': 100.0})
        cls.product.product_tmpl_id.write({
            'ff_show_in_app': True, 'ff_mrp': 120.0, 'ff_ptr': 100.0, 'ff_pts': 85.0})
        cls.Demand = cls.env['ff.demand']

    def _demand(self, partner, qty, uuid=None):
        return self.Demand.ff_create_from_app(self.employee, partner, {
            'lines': [{'product_id': self.product.id, 'qty': qty}],
            'uuid': uuid,
        })

    def test_trade_prices_give_the_margins(self):
        template = self.product.product_tmpl_id
        # Margin on what the buyer paid: buy at 100, sell at 120 -> 20%.
        self.assertEqual(template.ff_retail_margin, 20.0)
        # Buy at 85, sell at 100 -> 17.65%.
        self.assertEqual(template.ff_stockist_margin, 17.65)
        self.assertEqual(self.product.ff_field_price(), 100.0)
        self.assertEqual(self.product.ff_distributor_price(), 85.0)

    def test_a_demand_is_priced_at_ptr_and_knows_its_distributor(self):
        demand = self._demand(self.shop_a, 10)
        self.assertEqual(demand.state, 'submitted')
        self.assertEqual(demand.line_ids.price_unit, 100.0, 'the outlet is quoted PTR')
        self.assertEqual(demand.distributor_id, self.distributor)
        self.assertEqual(demand.amount_total, 1000.0)

    def test_the_same_demand_is_never_taken_twice(self):
        first = self._demand(self.shop_a, 5, uuid='dem-1')
        again = self._demand(self.shop_a, 5, uuid='dem-1')
        self.assertEqual(first, again)

    def test_two_outlets_become_one_line_on_one_quotation(self):
        first = self._demand(self.shop_a, 10)
        second = self._demand(self.shop_b, 15)
        demands = first | second
        wizard = self.env['ff.demand.quotation'].with_context(active_ids=demands.ids).create({})
        self.assertEqual(len(wizard.line_ids), 1, 'same product, same distributor, one line')
        line = wizard.line_ids
        self.assertEqual(line.quantity, 25)
        self.assertEqual(line.outlets, 2)
        self.assertEqual(line.price_unit, 85.0, 'the distributor is quoted PTS')

        wizard.action_create()
        orders = demands.mapped('order_ids')
        self.assertEqual(len(orders), 1)
        self.assertEqual(orders.partner_id, self.distributor)
        self.assertEqual(orders.order_line.product_uom_qty, 25)
        self.assertEqual(demands.mapped('state'), ['quoted', 'quoted'])

    def test_quoting_less_leaves_the_rest_pending(self):
        demand = self._demand(self.shop_a, 20)
        wizard = self.env['ff.demand.quotation'].with_context(active_ids=demand.ids).create({})
        wizard.line_ids.quantity = 8
        wizard.action_create()
        self.assertEqual(demand.line_ids.quoted_quantity, 8)
        self.assertEqual(demand.state, 'partial')

        rest = self.env['ff.demand.quotation'].with_context(active_ids=demand.ids).create({})
        self.assertEqual(rest.line_ids.quantity, 12, 'only what is still pending comes up again')
        rest.action_create()
        self.assertEqual(demand.state, 'quoted')

    def test_a_demand_on_a_quotation_cannot_be_cancelled(self):
        demand = self._demand(self.shop_a, 4)
        self.env['ff.demand.quotation'].with_context(active_ids=demand.ids).create({}).action_create()
        with self.assertRaises(UserError):
            demand.action_cancel()

    def test_without_a_distributor_the_office_must_choose_one(self):
        orphan = self.env['res.partner'].create({
            'name': 'Orphan Shop', 'ff_is_client': True, 'ff_approval_state': 'approved',
            'ff_category_id': self.env.ref('ff_clients.contact_category_customer').id,
            'ff_employee_ids': [(6, 0, self.employee.ids)],
        })
        demand = self._demand(orphan, 3)
        self.assertFalse(demand.distributor_id)
        wizard = self.env['ff.demand.quotation'].with_context(active_ids=demand.ids).create({})
        with self.assertRaises(UserError):
            wizard.action_create()
        wizard.distributor_id = self.distributor.id
        wizard.action_create()
        self.assertEqual(demand.distributor_id, self.distributor)

    def test_the_sale_price_follows_pts_on_this_flow(self):
        product = self.env['product.product'].create({
            'name': 'Amox 500', 'sale_ok': True, 'list_price': 0.0})
        product.product_tmpl_id.write({'ff_pts': 62.0, 'ff_ptr': 78.0, 'ff_mrp': 95.0})
        self.assertEqual(product.product_tmpl_id.list_price, 62.0,
                         'the distributor is the customer, so the sale price is PTS')

    def test_a_chosen_sale_price_is_left_alone(self):
        template = self.product.product_tmpl_id
        template.write({'list_price': 91.0})
        self.assertEqual(template.list_price, 91.0, 'only a change to PTS moves the sale price')

    def test_the_direct_flow_never_touches_the_sale_price(self):
        self.env['ir.config_parameter'].sudo().set_param('ff_base.order_flow', 'direct')
        product = self.env['product.product'].create({
            'name': 'Direct Item', 'sale_ok': True, 'list_price': 200.0})
        product.product_tmpl_id.write({'ff_pts': 150.0})
        self.assertEqual(product.product_tmpl_id.list_price, 200.0)
        self.env['ir.config_parameter'].sudo().set_param('ff_base.order_flow', 'demand')

    def test_the_backfill_puts_pts_on_the_sale_price(self):
        self.env['ir.config_parameter'].sudo().set_param('ff_base.order_flow', 'direct')
        product = self.env['product.product'].create({
            'name': 'Backfill Item', 'sale_ok': True, 'list_price': 300.0})
        product.product_tmpl_id.write({'ff_pts': 210.0})
        self.assertEqual(product.product_tmpl_id.list_price, 300.0)
        product.product_tmpl_id.action_ff_apply_pts_price()
        self.assertEqual(product.product_tmpl_id.list_price, 210.0)
        self.env['ir.config_parameter'].sudo().set_param('ff_base.order_flow', 'demand')
