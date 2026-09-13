from odoo.tests import TransactionCase, tagged


@tagged('post_install', '-at_install', 'ff')
class TestApiReceipts(TransactionCase):

    def test_store_once_and_find(self):
        Receipt = self.env['ff.api.receipt']
        employee = self.env['hr.employee'].create({'name': 'Receipt Officer'})
        self.assertFalse(Receipt.ff_find('abc-123-uuid'))
        Receipt.ff_store('abc-123-uuid', employee, '/api/v1/orders', 201, '{"ok": true, "data": {"id": 7}}')
        Receipt.ff_store('abc-123-uuid', employee, '/api/v1/orders', 201, '{"ok": true, "data": {"id": 8}}')
        found = Receipt.ff_find('abc-123-uuid')
        self.assertEqual(len(found), 1)
        self.assertIn('"id": 7', found.response)
        self.assertEqual(found.status, 201)
