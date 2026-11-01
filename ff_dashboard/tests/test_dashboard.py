from datetime import datetime, timedelta

import pytz

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


@tagged('post_install', '-at_install', 'ff')
class TestTimeline(TransactionCase):
    """The day replayed: punches, halts and the travel between them."""

    @classmethod
    def setUpClass(cls):
        super().setUpClass()
        cls.Dashboard = cls.env['ff.dashboard']
        cls.employee = cls.env['hr.employee'].create({'name': 'Timeline Officer', 'tz': 'UTC'})
        cls.shop = cls.env['res.partner'].create({
            'name': 'Timeline Shop', 'ff_is_client': True,
            'ff_category_id': cls.env.ref('ff_clients.contact_category_customer').id,
            'ff_employee_ids': [(6, 0, cls.employee.ids)],
            'partner_latitude': 10.0, 'partner_longitude': 76.0,
        })

    def test_an_empty_day_answers_with_empty_lists(self):
        data = self.Dashboard.ff_employee_timeline(self.employee.id)
        self.assertEqual(data['events'], [])
        self.assertEqual(data['path'], [])
        self.assertEqual(data['summary']['visits'], 0)

    def test_the_day_is_told_in_order(self):
        now = fields.Datetime.now()
        self.env['hr.attendance'].create({
            'employee_id': self.employee.id,
            'check_in': now - timedelta(hours=3),
            'check_out': now,
        })
        self.env['ff.visit'].ff_check_in(self.employee, self.shop, {'lat': 10.0, 'lng': 76.0})
        data = self.Dashboard.ff_employee_timeline(self.employee.id)
        kinds = [event['kind'] for event in data['events']]
        self.assertEqual(kinds[0], 'punch_in')
        self.assertIn('visit', kinds)
        self.assertIn('punch_out', kinds)
        times = [event['at'] for event in data['events'] if event['kind'] != 'travel']
        self.assertEqual(times, sorted(times), 'events must read in the order they happened')

    def test_the_path_follows_the_pings(self):
        now = fields.Datetime.now()
        for index in range(5):
            self.env['ff.location.ping'].sudo().create({
                'employee_id': self.employee.id,
                'ts': now - timedelta(minutes=50 - index * 10),
                'latitude': 10.0 + index * 0.01,
                'longitude': 76.0,
                'accuracy': 10,
            })
        data = self.Dashboard.ff_employee_timeline(self.employee.id)
        self.assertEqual(len(data['path']), 5)
        self.assertGreater(data['summary']['distance_km'], 0)

    def test_somebody_outside_my_scope_gives_nothing(self):
        stranger = self.env['hr.employee'].create({'name': 'Stranger'})
        officer = self.env['res.users'].create({
            'name': 'Scoped', 'login': 'ff_timeline_scope',
            'groups_id': [(6, 0, [self.env.ref('ff_base.group_ff_officer').id,
                                  self.env.ref('base.group_user').id])],
        })
        self.env['hr.employee'].create({
            'name': 'Scoped Employee', 'user_id': officer.id, 'ff_access_scope': 'own'})
        data = self.Dashboard.with_user(officer).ff_employee_timeline(stranger.id)
        self.assertEqual(data['events'], [])


@tagged('post_install', '-at_install', 'ff')
class TestOrgTree(TransactionCase):
    """The hierarchy view: people nested under their manager."""

    @classmethod
    def setUpClass(cls):
        super().setUpClass()
        cls.Dashboard = cls.env['ff.dashboard']
        cls.head = cls.env['hr.employee'].create({'name': 'Regional Head', 'job_title': 'RSM'})
        cls.team = cls.env['ff.team'].create({'name': 'South Team'})
        cls.manager = cls.env['hr.employee'].create({
            'name': 'Area Manager', 'parent_id': cls.head.id, 'ff_team_id': cls.team.id})
        cls.officer = cls.env['hr.employee'].create({
            'name': 'Field Officer', 'parent_id': cls.manager.id, 'ff_team_id': cls.team.id})

    def _find(self, nodes, name):
        for node in nodes:
            if node['name'] == name:
                return node
            found = self._find(node['children'], name)
            if found:
                return found
        return None

    def test_people_sit_under_their_manager(self):
        tree = self.Dashboard.ff_org_tree()
        head = self._find(tree['roots'], 'Regional Head')
        self.assertTrue(head, 'the top of the chain is a root')
        manager = self._find([head], 'Area Manager')
        self.assertTrue(manager)
        self.assertTrue(self._find([manager], 'Field Officer'))

    def test_a_manager_counts_everybody_below_them(self):
        tree = self.Dashboard.ff_org_tree()
        head = self._find(tree['roots'], 'Regional Head')
        self.assertEqual(head['reports'], 2, 'the whole branch counts, not just direct reports')
        manager = self._find([head], 'Area Manager')
        self.assertEqual(manager['reports'], 1)

    def test_the_card_carries_what_the_chart_shows(self):
        tree = self.Dashboard.ff_org_tree()
        manager = self._find(tree['roots'], 'Area Manager') or self._find(
            [self._find(tree['roots'], 'Regional Head')], 'Area Manager')
        self.assertEqual(manager['team'], 'South Team')
        self.assertIn('/web/image/hr.employee/', manager['avatar'])


@tagged('post_install', '-at_install', 'ff')
class TestReports(TransactionCase):
    """The sections a manager reads: attendance, expenses, orders, leaves."""

    @classmethod
    def setUpClass(cls):
        super().setUpClass()
        cls.Dashboard = cls.env['ff.dashboard']
        cls.employee = cls.env['hr.employee'].create({'name': 'Report Officer', 'tz': 'UTC'})

    def test_attendance_counts_the_days_somebody_worked(self):
        now = fields.Datetime.now()
        self.env['hr.attendance'].create({
            'employee_id': self.employee.id,
            'check_in': now - timedelta(hours=8),
            'check_out': now,
        })
        report = self.Dashboard.ff_attendance_report('month')
        row = next(row for row in report['rows'] if row['id'] == self.employee.id)
        self.assertEqual(row['present'], 1)
        self.assertGreater(row['hours'], 7)
        self.assertEqual(len(report['series']), report['days'], 'one bar per day of the period')
        self.assertGreaterEqual(report['kpis']['punches'], 1)

    def test_every_period_answers_for_every_section(self):
        for period in ('today', 'week', 'month'):
            attendance = self.Dashboard.ff_attendance_report(period)
            self.assertEqual(attendance['period'], period)
            orders = self.Dashboard.ff_order_report(period)
            self.assertIn(orders['flow'], ('direct', 'demand'))
            self.assertIsInstance(orders['series'], list)

    def test_the_order_report_follows_the_flow_setting(self):
        Param = self.env['ir.config_parameter'].sudo()
        Param.set_param('ff_base.order_flow', 'direct')
        self.assertEqual(self.Dashboard.ff_order_report()['flow'], 'direct')
        if 'ff.demand' in self.env:
            Param.set_param('ff_base.order_flow', 'demand')
            report = self.Dashboard.ff_order_report()
            self.assertEqual(report['flow'], 'demand')
            self.assertIn('pending', report['kpis'])
        Param.set_param('ff_base.order_flow', 'direct')

    def test_a_missing_module_reports_nothing_rather_than_failing(self):
        result = self.Dashboard.ff_leaves_report()
        self.assertTrue(result is None or 'kpis' in result)


@tagged('post_install', '-at_install', 'ff')
class TestFiltersAndCalendar(TransactionCase):
    """Filters narrow every report, and the month grid tells the day apart."""

    @classmethod
    def setUpClass(cls):
        super().setUpClass()
        cls.Dashboard = cls.env['ff.dashboard']
        cls.sales = cls.env['hr.department'].create({'name': 'Sales Dept'})
        cls.medical = cls.env['hr.department'].create({'name': 'Medical Dept'})
        cls.team = cls.env['ff.team'].create({'name': 'North Team'})
        cls.one = cls.env['hr.employee'].create({
            'name': 'Filter One', 'tz': 'UTC', 'department_id': cls.sales.id, 'ff_team_id': cls.team.id})
        cls.two = cls.env['hr.employee'].create({
            'name': 'Filter Two', 'tz': 'UTC', 'department_id': cls.medical.id})

    def test_the_filters_offer_only_what_is_in_scope(self):
        options = self.Dashboard.ff_filter_options()
        names = [row['name'] for row in options['employees']]
        self.assertIn('Filter One', names)
        self.assertIn('Sales Dept', [row['name'] for row in options['departments']])
        self.assertIn('North Team', [row['name'] for row in options['teams']])

    def test_one_employee_narrows_the_report(self):
        report = self.Dashboard.ff_attendance_report('month', {'employee_id': self.one.id})
        self.assertEqual(report['employee_ids'], [self.one.id])
        self.assertEqual(report['kpis']['headcount'], 1)

    def test_a_department_narrows_the_report(self):
        report = self.Dashboard.ff_attendance_report('month', {'department_id': self.medical.id})
        self.assertEqual(report['employee_ids'], [self.two.id])

    def test_a_team_narrows_the_report(self):
        report = self.Dashboard.ff_expense_report('month', {'team_id': self.team.id})
        if report is not None:
            self.assertEqual(report['employee_ids'], [self.one.id])

    def test_the_calendar_is_a_month_of_boxes(self):
        now = fields.Datetime.now()
        self.env['hr.attendance'].create({
            'employee_id': self.one.id, 'check_in': now - timedelta(hours=6), 'check_out': now})
        calendar = self.Dashboard.ff_attendance_calendar(None, {'employee_id': self.one.id})
        cells = [cell for week in calendar['weeks'] for cell in week if cell]
        self.assertTrue(cells, 'the month has days')
        self.assertTrue(all(len(week) == 7 for week in calendar['weeks']), 'seven columns a week')
        today = next(cell for cell in cells if cell['today'])
        self.assertEqual(today['present'], 1)
        self.assertEqual(today['boxes'][0]['status'], 'present')

    def test_days_still_to_come_are_not_counted_as_absence(self):
        calendar = self.Dashboard.ff_attendance_calendar()
        future = [cell for week in calendar['weeks'] for cell in week if cell and cell['future']]
        for cell in future:
            self.assertEqual(cell['absent'], 0)
            self.assertTrue(all(box['status'] == 'future' for box in cell['boxes']))


@tagged('post_install', '-at_install', 'ff')
class TestPeriodRange(TransactionCase):
    """Named spans and custom dates, including months already gone."""

    @classmethod
    def setUpClass(cls):
        super().setUpClass()
        cls.Dashboard = cls.env['ff.dashboard']

    def test_the_named_spans_cover_what_they_say(self):
        today = fields.Date.context_today(self.Dashboard)
        self.assertEqual(self.Dashboard._ff_range('today'), (today, today))
        self.assertEqual(self.Dashboard._ff_range('yesterday'),
                         (today - timedelta(days=1), today - timedelta(days=1)))
        start, end = self.Dashboard._ff_range('month')
        self.assertEqual(start, today.replace(day=1))
        self.assertEqual(end, today)

    def test_last_month_is_the_whole_month_before(self):
        today = fields.Date.context_today(self.Dashboard)
        start, end = self.Dashboard._ff_range('last_month')
        self.assertEqual(start.day, 1)
        self.assertEqual((end + timedelta(days=1)).day, 1, 'it ends on the last day of that month')
        self.assertLess(end, today.replace(day=1))

    def test_custom_dates_are_taken_as_given(self):
        start, end = self.Dashboard._ff_range('custom', {'date_from': '2026-04-01', 'date_to': '2026-04-30'})
        self.assertEqual(start.isoformat(), '2026-04-01')
        self.assertEqual(end.isoformat(), '2026-04-30')

    def test_a_backwards_range_is_turned_around(self):
        start, end = self.Dashboard._ff_range('custom', {'date_from': '2026-06-30', 'date_to': '2026-06-01'})
        self.assertEqual(start.isoformat(), '2026-06-01')
        self.assertEqual(end.isoformat(), '2026-06-30')

    def test_a_past_range_reports_on_that_range(self):
        report = self.Dashboard.ff_attendance_report(
            'custom', {'date_from': '2026-01-01', 'date_to': '2026-01-31'})
        self.assertEqual(report['start'], '2026-01-01')
        self.assertEqual(report['end'], '2026-01-31')
        self.assertEqual(report['days'], 31)
        self.assertEqual(len(report['series']), 31, 'one bar per day of the chosen range')

    def test_the_label_says_the_range(self):
        label = self.Dashboard.ff_period_label('custom', {'date_from': '2026-02-01', 'date_to': '2026-02-28'})
        self.assertIn('Feb', label)


@tagged('post_install', '-at_install', 'ff')
class TestPanelToday(TransactionCase):
    """The panel's idea of today, for a user with no timezone set."""

    @classmethod
    def setUpClass(cls):
        super().setUpClass()
        cls.Dashboard = cls.env['ff.dashboard']

    def test_today_follows_the_user_timezone(self):
        self.env.user.tz = 'Asia/Kolkata'
        expected = datetime.now(pytz.utc).astimezone(pytz.timezone('Asia/Kolkata')).date()
        self.assertEqual(self.Dashboard._ff_today(), expected)
        self.assertEqual(self.Dashboard._ff_range('today'), (expected, expected))

    def test_without_a_user_timezone_the_company_decides(self):
        self.env.user.tz = False
        self.env.user.employee_id.tz = False if self.env.user.employee_id else False
        self.env.company.partner_id.tz = 'Asia/Kolkata'
        expected = datetime.now(pytz.utc).astimezone(pytz.timezone('Asia/Kolkata')).date()
        self.assertEqual(self.Dashboard._ff_today(), expected,
                         'a night in India must not be reported as yesterday')
