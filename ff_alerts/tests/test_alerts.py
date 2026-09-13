from odoo.tests import TransactionCase, tagged


@tagged('post_install', '-at_install', 'ff')
class TestAlerts(TransactionCase):

    @classmethod
    def setUpClass(cls):
        super().setUpClass()
        cls.manager = cls.env['hr.employee'].create({'name': 'Alert Manager', 'ff_access_scope': 'hierarchy'})
        cls.officer = cls.env['hr.employee'].create({'name': 'Alert Officer', 'parent_id': cls.manager.id, 'tz': 'UTC'})
        category = cls.env.ref('ff_clients.contact_category_customer')
        cls.shop = cls.env['res.partner'].create({
            'name': 'Alert Stores', 'ff_is_client': True, 'ff_category_id': category.id,
            'ff_employee_ids': [(6, 0, cls.officer.ids)], 'partner_latitude': 10.0, 'partner_longitude': 76.0})

    def test_offsite_visit_alerts_manager(self):
        self.env['ff.visit'].ff_check_in(self.officer, self.shop, {'lat': 10.05, 'lng': 76.0, 'offsite': True})
        alert = self.env['ff.alert'].search([('employee_id', '=', self.officer.id), ('kind', '=', 'offsite_visit')])
        self.assertEqual(len(alert), 1)
        self.assertEqual(alert.manager_id, self.manager)
        self.assertIn('Alert Stores', alert.message)

    def test_same_alert_not_repeated(self):
        Alert = self.env['ff.alert']
        first = Alert.ff_raise(self.officer, 'no_signal', 'gone quiet')
        second = Alert.ff_raise(self.officer, 'no_signal', 'still quiet')
        self.assertTrue(first)
        self.assertFalse(second)

    def test_switched_off_kind(self):
        self.env['ir.config_parameter'].sudo().set_param('ff_alerts.kind_inactive', 'False')
        self.assertFalse(self.env['ff.alert'].ff_raise(self.officer, 'inactive', 'not moving'))

    def test_digest_row(self):
        today = self.officer._ff_today()
        row = self.env['ff.digest']._row(self.officer, today, today)
        self.assertEqual(row['visits'], 0)
        html = self.env['ff.digest']._html(self.manager, 'Daily summary', 'today', [row])
        self.assertIn('Alert Officer', html)
