from odoo.tests import TransactionCase, tagged


@tagged('post_install', '-at_install', 'ff')
class TestAppReports(TransactionCase):

    @classmethod
    def setUpClass(cls):
        super().setUpClass()
        cls.employee = cls.env['hr.employee'].create({'name': 'Report Officer', 'tz': 'Asia/Kolkata'})
        category = cls.env.ref('ff_clients.contact_category_customer')
        cls.shop = cls.env['res.partner'].create({
            'name': 'Report Stores', 'ff_is_client': True, 'ff_category_id': category.id,
            'ff_employee_ids': [(6, 0, cls.employee.ids)], 'partner_latitude': 10.0, 'partner_longitude': 76.0,
        })
        cls.Report = cls.env['ff.app.report']

    def test_catalogue_and_every_report_runs(self):
        catalogue = self.Report.ff_catalogue()
        keys = {row['key'] for row in catalogue}
        self.assertIn('attendance', keys)
        self.assertIn('visits', keys)
        today = self.employee._ff_today()
        for key in keys | {'orders'}:
            data = self.Report.ff_run(key, self.employee, self.employee, today, today)
            self.assertIsNotNone(data, key)
            self.assertTrue(data['columns'], key)
            for column in data['columns']:
                if column['total']:
                    self.assertIn(column['key'], data['totals'])

    def test_visits_rows_and_excel(self):
        self.env['ff.visit'].ff_check_in(self.employee, self.shop, {'lat': 10.0, 'lng': 76.0})
        today = self.employee._ff_today()
        data = self.Report.ff_run('visits', self.employee, self.employee, today, today)
        self.assertEqual(len(data['rows']), 1)
        self.assertEqual(data['rows'][0]['customer'], 'Report Stores')
        content = self.Report.ff_xlsx(data, 'Report Officer')
        self.assertEqual(content[:2], b'PK')  # an xlsx is a zip

    def test_unknown_report(self):
        today = self.employee._ff_today()
        self.assertIsNone(self.Report.ff_run('nope', self.employee, self.employee, today, today))
