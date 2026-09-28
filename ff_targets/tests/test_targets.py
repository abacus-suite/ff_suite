from odoo.exceptions import ValidationError
from odoo.tests import TransactionCase, tagged


@tagged('post_install', '-at_install', 'ff')
class TestTargets(TransactionCase):

    @classmethod
    def setUpClass(cls):
        super().setUpClass()
        cls.employee = cls.env['hr.employee'].create({'name': 'Target Officer', 'tz': 'Asia/Kolkata'})
        category = cls.env.ref('ff_clients.contact_category_customer')
        cls.shop = cls.env['res.partner'].create({
            'name': 'Target Stores', 'ff_is_client': True, 'ff_category_id': category.id,
            'ff_employee_ids': [(6, 0, cls.employee.ids)], 'partner_latitude': 10.0, 'partner_longitude': 76.0,
        })

    def test_month_is_normalised_and_unique(self):
        today = self.employee._ff_today()
        target = self.env['ff.target'].create({'employee_id': self.employee.id, 'month': today, 'visit_target': 4})
        self.assertEqual(target.month.day, 1)
        with self.assertRaises(Exception):
            with self.env.cr.savepoint():
                self.env['ff.target'].create({'employee_id': self.employee.id, 'month': today})
        with self.assertRaises(ValidationError):
            target.visit_target = -1

    def test_achievement_counts_visits(self):
        today = self.employee._ff_today()
        target = self.env['ff.target'].create({
            'employee_id': self.employee.id, 'month': today, 'visit_target': 4, 'customer_target': 0})
        visit = self.env['ff.visit'].ff_check_in(self.employee, self.shop, {'lat': 10.0, 'lng': 76.0})
        visit.ff_check_out({})
        self.env['ff.visit'].ff_check_in(self.employee, self.shop, {'lat': 10.0, 'lng': 76.0})
        target.invalidate_recordset()
        self.assertEqual(target.visit_actual, 2)
        self.assertEqual(target.achievement, 50)
        progress = self.env['ff.target'].ff_progress(self.employee, today)
        self.assertEqual(progress['rows'][0]['achievement'], 50)

    def test_copy_to_next_month(self):
        today = self.employee._ff_today()
        target = self.env['ff.target'].create({'employee_id': self.employee.id, 'month': today, 'visit_target': 10})
        target.action_copy_to_next_month()
        target.action_copy_to_next_month()  # already there: not copied twice
        self.assertEqual(self.env['ff.target'].search_count([('employee_id', '=', self.employee.id)]), 2)


@tagged('post_install', '-at_install', 'ff')
class TestTargetSplitAndIncentive(TransactionCase):

    @classmethod
    def setUpClass(cls):
        super().setUpClass()
        Employee = cls.env['hr.employee']
        cls.head = Employee.create({'name': 'Sales Head', 'ff_access_scope': 'hierarchy'})
        cls.lead_a = Employee.create({'name': 'Lead A', 'parent_id': cls.head.id, 'ff_access_scope': 'hierarchy'})
        cls.rep_1 = Employee.create({'name': 'Rep One', 'parent_id': cls.lead_a.id})
        cls.rep_2 = Employee.create({'name': 'Rep Two', 'parent_id': cls.lead_a.id})
        cls.team_a = cls.env['ff.team'].create({'name': 'Team A', 'manager_id': cls.lead_a.id})
        (cls.lead_a | cls.rep_1 | cls.rep_2).write({'ff_team_id': cls.team_a.id})
        cls.month = cls.head._ff_today()

    def test_team_target_split_down_two_levels(self):
        team_target = self.env['ff.target'].create({
            'scope': 'team', 'team_id': self.team_a.id, 'month': self.month, 'sales_target': 50000})
        self.assertEqual(team_target.owner_id, self.lead_a)
        self.assertTrue(team_target.ff_can_split(self.lead_a))
        self.assertTrue(team_target.ff_can_split(self.head))  # above the owner
        self.assertFalse(team_target.ff_can_split(self.rep_1))
        children = team_target.ff_split(self.lead_a, [
            {'scope': 'employee', 'id': self.rep_1.id, 'sales': 30000},
            {'scope': 'employee', 'id': self.rep_2.id, 'sales': 20000},
        ])
        self.assertEqual(len(children), 2)
        self.assertEqual(team_target.unallocated, 'Fully split')
        with self.assertRaises(ValidationError):
            team_target.ff_split(self.lead_a, [{'scope': 'employee', 'id': self.rep_1.id, 'sales': 40000}])
        # Re-sending the same split updates instead of duplicating.
        team_target.ff_split(self.lead_a, [{'scope': 'employee', 'id': self.rep_1.id, 'sales': 25000}])
        self.assertEqual(len(team_target.child_ids), 2)

    def test_incentive_conditions(self):
        target = self.env['ff.target'].create({
            'scope': 'employee', 'employee_id': self.rep_1.id, 'month': self.month,
            'visit_target': 10, 'sales_target': 1000})
        Rule = self.env['ff.incentive.rule']
        actual = {'visits': 10, 'customers': 0, 'sales': 500.0, 'collections': 0.0}
        every = Rule.create({'name': 'All', 'condition': 'all', 'amount': 2000})
        self.assertEqual(every.ff_evaluate(target, actual)[0], 0.0)
        each = Rule.create({'name': 'Each', 'condition': 'each', 'visit_amount': 300, 'sales_amount': 700})
        self.assertEqual(each.ff_evaluate(target, actual)[0], 300.0)
        share = Rule.create({'name': 'Share', 'condition': 'pro_rata', 'threshold_pct': 50,
                             'visit_amount': 300, 'sales_amount': 700})
        self.assertEqual(share.ff_evaluate(target, actual)[0], 300.0 + 350.0)
        actual['sales'] = 1000.0
        self.assertEqual(every.ff_evaluate(target, actual)[0], 2000.0)

    def test_leaderboard_ranks(self):
        board = self.env['ff.target'].ff_leaderboard(self.lead_a | self.rep_1 | self.rep_2, self.month)
        self.assertEqual([row['rank'] for row in board], [1, 2, 3])
