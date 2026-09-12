from odoo import fields
from odoo.tests import TransactionCase, tagged


@tagged('post_install', '-at_install', 'ff')
class TestDashboard(TransactionCase):

    @classmethod
    def setUpClass(cls):
        super().setUpClass()
        cls.Dashboard = cls.env['ff.dashboard']
        cls.manager = cls.env['hr.employee'].create({'name': 'Panel Manager', 'ff_access_scope': 'hierarchy'})
        cls.officer = cls.env['hr.employee'].create({'name': 'Panel Officer', 'parent_id': cls.manager.id})

    def test_the_panel_opens_with_everybody_counted(self):
        data = self.Dashboard.ff_dashboard_data()
        names = [row['name'] for row in data['people']]
        self.assertIn('Panel Officer', names)
        self.assertEqual(data['realtime']['total'], len(data['people']))
        self.assertEqual(data['realtime']['punched_in'] + data['realtime']['punched_out'],
                         data['realtime']['total'])

    def test_punching_in_moves_the_numbers(self):
        status = self.env['ff.employee.status']._ff_get(self.officer)
        status.write({'punched_in': True, 'punched_in_at': fields.Datetime.now(),
                      'last_ping_at': fields.Datetime.now(), 'latitude': 10.0, 'longitude': 76.0})
        data = self.Dashboard.ff_dashboard_data()
        self.assertGreaterEqual(data['realtime']['punched_in'], 1)
        person = next(row for row in data['people'] if row['id'] == self.officer.id)
        self.assertTrue(person['punched_in'])
        self.assertEqual(person['lat'], 10.0)

    def test_teams_add_up_to_the_headcount(self):
        data = self.Dashboard.ff_dashboard_data()
        counted = sum(team['in'] + team['out'] for team in data['teams'])
        self.assertEqual(counted, data['realtime']['total'])

    def test_every_period_answers(self):
        for period in ('today', 'week', 'month'):
            data = self.Dashboard.ff_dashboard_data(period)
            self.assertEqual(data['period'], period)
            self.assertIsInstance(data['working_hours'], list)
