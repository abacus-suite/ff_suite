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


@tagged('post_install', '-at_install', 'ff')
class TestEmployeeDay(TransactionCase):
    """The tabs under a Live Location card."""

    @classmethod
    def setUpClass(cls):
        super().setUpClass()
        cls.Dashboard = cls.env['ff.dashboard']
        cls.employee = cls.env['hr.employee'].create({'name': 'Day Officer', 'tz': 'UTC'})
        cls.shop = cls.env['res.partner'].create({
            'name': 'Day Shop', 'ff_is_client': True,
            'ff_category_id': cls.env.ref('ff_clients.contact_category_customer').id,
            'ff_employee_ids': [(6, 0, cls.employee.ids)],
            'partner_latitude': 10.0, 'partner_longitude': 76.0,
        })

    def test_a_visit_today_shows_under_the_card(self):
        visit = self.env['ff.visit'].ff_check_in(self.employee, self.shop, {'lat': 10.0, 'lng': 76.0})
        day = self.Dashboard.ff_employee_day(self.employee.id)
        self.assertEqual(len(day['visits']), 1)
        self.assertEqual(day['visits'][0]['client'], self.shop.display_name)
        self.assertEqual(day['visits'][0]['state'], visit.state)

    def test_somebody_outside_my_scope_shows_nothing(self):
        stranger = self.env['hr.employee'].create({'name': 'Not Mine'})
        officer = self.env['res.users'].create({
            'name': 'Own Scope', 'login': 'ff_own_scope',
            'groups_id': [(6, 0, [self.env.ref('ff_base.group_ff_officer').id,
                                  self.env.ref('base.group_user').id])],
        })
        self.env['hr.employee'].create({
            'name': 'Own Scope Employee', 'user_id': officer.id, 'ff_access_scope': 'own'})
        day = self.Dashboard.with_user(officer).ff_employee_day(stranger.id)
        self.assertEqual(day['visits'], [])
