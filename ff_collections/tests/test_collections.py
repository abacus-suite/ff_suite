from datetime import timedelta

from odoo import fields
from odoo.exceptions import UserError
from odoo.tests import TransactionCase, tagged


@tagged('post_install', '-at_install', 'ff')
class TestCollections(TransactionCase):

    @classmethod
    def setUpClass(cls):
        super().setUpClass()
        Param = cls.env['ir.config_parameter'].sudo()
        Param.set_param('ff_base.payment_collection', 'True')
        Param.set_param('ff_collections.max_days', '3')
        Param.set_param('ff_collections.max_amount', '5000')
        cls.manager = cls.env['hr.employee'].create({'name': 'Cash Manager', 'ff_access_scope': 'hierarchy'})
        cls.employee = cls.env['hr.employee'].create({
            'name': 'Cash Officer', 'tz': 'UTC', 'parent_id': cls.manager.id,
        })
        cls.shop = cls.env['res.partner'].create({
            'name': 'Cash Shop', 'ff_is_client': True,
            'ff_category_id': cls.env.ref('ff_clients.contact_category_customer').id,
            'ff_employee_ids': [(6, 0, cls.employee.ids)],
            'partner_latitude': 10.0, 'partner_longitude': 76.0,
        })
        cls.cash = cls.env.ref('ff_collections.collection_mode_cash')
        cls.online = cls.env.ref('ff_collections.collection_mode_online')
        cls.cheque = cls.env.ref('ff_collections.collection_mode_cheque')
        cls.Collection = cls.env['ff.collection']
        cls.Deposit = cls.env['ff.collection.deposit']

    def _collect(self, amount, mode=None, **extra):
        return self.Collection.ff_create_from_app(self.employee, dict(
            {'partner_id': self.shop.id, 'mode_id': (mode or self.cash).id, 'amount': amount}, **extra))

    def test_mode_rules(self):
        with self.assertRaises(UserError):  # online needs a reference
            self._collect(500, self.online)
        online = self._collect(500, self.online, reference='UPI-9911')
        self.assertEqual(online.state, 'received', 'online money never reaches the employee')
        with self.assertRaises(UserError):  # cheque needs a photo too
            self._collect(700, self.cheque, reference='CHQ-1')
        cheque = self._collect(700, self.cheque, reference='CHQ-1', photos=['iVBORw0KGgo='])
        self.assertEqual(cheque.state, 'collected')
        self.assertEqual(cheque.photo_count, 1)

    def test_amount_limit_blocks_check_in(self):
        self._collect(6000)
        status = self.Collection.ff_pending_status(self.employee)
        self.assertTrue(status['over_amount'])
        with self.assertRaises(UserError):
            self.env['ff.visit'].ff_check_in(self.employee, self.shop, {'lat': 10.0, 'lng': 76.0})

    def test_days_limit_blocks_check_in(self):
        old = self._collect(100)
        old.sudo().date = fields.Datetime.now() - timedelta(days=4)
        self.assertTrue(self.Collection.ff_pending_status(self.employee)['over_days'])
        with self.assertRaises(UserError):
            self.env['ff.visit'].ff_check_in(self.employee, self.shop, {'lat': 10.0, 'lng': 76.0})

    def test_deposit_flow_releases_the_block(self):
        self._collect(6000, uuid='col-1')
        self.assertEqual(self.Collection.ff_create_from_app(self.employee, {'uuid': 'col-1'}).amount, 6000)
        deposit = self.Deposit.ff_submit_from_app(self.employee, {})
        self.assertEqual(deposit.state, 'submitted')
        self.assertEqual(deposit.amount, 6000)
        self.assertFalse(self.Collection.ff_pending_status(self.employee)['blocked'])
        deposit._ff_decide_as(self.manager, True)
        self.assertEqual(deposit.state, 'received')
        self.assertEqual(deposit.collection_ids.mapped('state'), ['received'])
        # A visit is possible again
        visit = self.env['ff.visit'].ff_check_in(self.employee, self.shop, {'lat': 10.0, 'lng': 76.0})
        self.assertTrue(visit)

    def test_rejected_deposit_returns_money_to_the_employee(self):
        self._collect(200)
        deposit = self.Deposit.ff_submit_from_app(self.employee, {})
        deposit._ff_decide_as(self.manager, False)
        self.assertEqual(deposit.state, 'rejected')
        self.assertEqual(self.Collection.ff_pending_status(self.employee)['count'], 1)
