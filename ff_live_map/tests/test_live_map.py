from odoo import fields
from odoo.tests import TransactionCase, tagged


@tagged('post_install', '-at_install', 'ff')
class TestLiveMap(TransactionCase):

    @classmethod
    def setUpClass(cls):
        super().setUpClass()
        cls.manager = cls.env['hr.employee'].create({'name': 'Map Manager', 'ff_access_scope': 'hierarchy'})
        cls.officer = cls.env['hr.employee'].create({'name': 'Map Officer', 'parent_id': cls.manager.id})
        cls.Status = cls.env['ff.employee.status']

    def _status(self, employee, **vals):
        status = self.Status._ff_get(employee)
        status.write(dict({'punched_in': True, 'last_ping_at': fields.Datetime.now(),
                           'latitude': 10.0, 'longitude': 76.0}, **vals))
        return status

    def test_the_key_travels_with_the_positions(self):
        self.env['ir.config_parameter'].sudo().set_param('ff_base.google_maps_key', 'AIza-test')
        self.assertEqual(self.Status.ff_live_map()['google_maps_key'], 'AIza-test')

    def test_states_say_what_somebody_is_doing(self):
        self._status(self.officer)
        rows = {row['id']: row for row in self.Status.ff_live_map()['people']}
        self.assertEqual(rows[self.officer.id]['state'], 'moving')

        self._status(self.officer, is_inactive=True)
        rows = {row['id']: row for row in self.Status.ff_live_map()['people']}
        self.assertEqual(rows[self.officer.id]['state'], 'inactive')

        self._status(self.officer, is_inactive=False, is_signal_lost=True)
        rows = {row['id']: row for row in self.Status.ff_live_map()['people']}
        self.assertEqual(rows[self.officer.id]['state'], 'no_signal')

        self._status(self.officer, is_signal_lost=False, punched_in=False)
        rows = {row['id']: row for row in self.Status.ff_live_map()['people']}
        self.assertEqual(rows[self.officer.id]['state'], 'off')

    def test_a_position_that_was_never_sent_is_not_drawn(self):
        self.Status._ff_get(self.officer).write({'punched_in': True, 'last_ping_at': False})
        rows = {row['id']: row for row in self.Status.ff_live_map()['people']}
        self.assertFalse(rows[self.officer.id]['lat'])


@tagged('post_install', '-at_install', 'ff')
class TestMapUsage(TransactionCase):

    @classmethod
    def setUpClass(cls):
        super().setUpClass()
        cls.Usage = cls.env['ff.map.usage']
        cls.employee = cls.env['hr.employee'].create({'name': 'Tile User'})
        Param = cls.env['ir.config_parameter'].sudo()
        Param.set_param('ff_base.map_free_tiles', '100')
        Param.set_param('ff_base.map_price_tiles', '53')
        Param.set_param('ff_base.map_free_loads', '10')
        Param.set_param('ff_base.map_price_loads', '620')
        Param.set_param('ff_base.map_budget', '2000')

    def test_counts_add_up_in_one_row_per_day(self):
        self.Usage.ff_record('tiles', 40, employee=self.employee)
        self.Usage.ff_record('tiles', 35, employee=self.employee)
        rows = self.Usage.search([('kind', '=', 'tiles'), ('employee_id', '=', self.employee.id)])
        self.assertEqual(len(rows), 1)
        self.assertEqual(rows.count, 75)

    def test_the_free_tier_costs_nothing(self):
        self.Usage.ff_record('tiles', 80, employee=self.employee)
        summary = self.Usage.ff_usage_summary()
        self.assertEqual(summary['tiles']['used'], 80)
        self.assertEqual(summary['tiles']['free_left'], 20)
        self.assertEqual(summary['cost'], 0)

    def test_above_the_free_tier_the_cost_is_estimated(self):
        self.Usage.ff_record('tiles', 1100, employee=self.employee)  # 1000 billable
        self.Usage.ff_record('web_map', 20)                          # 10 billable
        summary = self.Usage.ff_usage_summary()
        self.assertEqual(summary['tiles']['cost'], 53.0)
        self.assertEqual(summary['web_map']['cost'], 6.2)
        self.assertEqual(summary['cost'], 59.2)
        self.assertFalse(summary['over_budget'])
        self.assertEqual(summary['budget_left'], 1940.8)

    def test_a_bad_count_is_ignored(self):
        self.assertFalse(self.Usage.ff_record('tiles', 0, employee=self.employee))
        self.assertFalse(self.Usage.ff_record('nonsense', 5, employee=self.employee))
