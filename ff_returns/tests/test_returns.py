from odoo.exceptions import UserError
from odoo.tests import TransactionCase, tagged


@tagged('post_install', '-at_install', 'ff')
class TestReturns(TransactionCase):

    @classmethod
    def setUpClass(cls):
        super().setUpClass()
        cls.manager = cls.env['hr.employee'].create({'name': 'Return Manager', 'ff_access_scope': 'hierarchy'})
        cls.officer = cls.env['hr.employee'].create({'name': 'Return Officer', 'parent_id': cls.manager.id})
        category = cls.env.ref('ff_clients.contact_category_customer')
        cls.shop = cls.env['res.partner'].create({
            'name': 'Return Stores', 'ff_is_client': True, 'ff_category_id': category.id,
            'ff_employee_ids': [(6, 0, cls.officer.ids)]})
        cls.product = cls.env['product.product'].create({'name': 'Soap', 'lst_price': 25.0, 'sale_ok': True})

    def test_report_approve_credit(self):
        Return = self.env['ff.return']
        with self.assertRaises(UserError):
            Return.ff_create_from_app(self.officer, self.shop, {'lines': []})
        record = Return.ff_create_from_app(self.officer, self.shop, {
            'reason': 'damaged', 'lines': [{'product_id': self.product.id, 'qty': 4}], 'photos': ['iVBORw0KGgo=']})
        self.assertTrue(record.name.startswith('RET/'))
        self.assertEqual(record.quantity_total, 4)
        self.assertEqual(record.photo_count, 1)
        with self.assertRaises(UserError):
            record.action_create_credit_note()  # not approved yet
        record.ff_decide_as(self.manager, True)
        self.assertEqual(record.state, 'approved')
        with self.assertRaises(UserError):
            record.ff_decide_as(self.manager, False)  # already decided
        if not self.env['account.journal'].search([('type', '=', 'sale'), ('company_id', '=', record.company_id.id)], limit=1):
            return  # no chart of accounts in this database: nothing to credit into
        record.action_create_credit_note()
        self.assertEqual(record.state, 'credited')
        self.assertEqual(record.credit_note_id.move_type, 'out_refund')
