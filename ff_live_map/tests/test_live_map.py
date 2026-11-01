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

    def test_everybody_is_listed_even_without_a_status(self):
        # An employee who never opened the app must still be on the list, as "off".
        rows = {row['id']: row for row in self.Status.ff_live_map()['people']}
        self.assertIn(self.officer.id, rows)
        self.assertEqual(rows[self.officer.id]['state'], 'off')
        self.assertFalse(rows[self.officer.id]['lat'])

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

    def test_usage_is_broken_down_by_employee(self):
        other = self.env['hr.employee'].create({'name': 'Second User'})
        self.Usage.ff_record('tiles', 300, employee=self.employee)
        self.Usage.ff_record('tiles', 80, employee=other)
        rows = self.Usage.ff_usage_by_employee()
        self.assertEqual([row['name'] for row in rows[:2]], ['Tile User', 'Second User'])
        self.assertEqual(rows[0]['tiles'], 300)

    def test_a_bad_count_is_ignored(self):
        self.assertFalse(self.Usage.ff_record('tiles', 0, employee=self.employee))
        self.assertFalse(self.Usage.ff_record('nonsense', 5, employee=self.employee))


@tagged('post_install', '-at_install', 'ff')
class TestGeocodeCache(TransactionCase):
    """The address cache decides when Google is worth paying for."""

    @classmethod
    def setUpClass(cls):
        super().setUpClass()
        cls.employee = cls.env['hr.employee'].create({'name': 'Roaming Officer'})
        cls.status = cls.env['ff.employee.status']._ff_get(cls.employee)

    def test_a_fix_without_an_address_needs_one(self):
        self.status.write({'latitude': 10.0, 'longitude': 76.0})
        self.assertIn(self.status, self.status._ff_needs_address())

    def test_standing_still_reuses_the_cached_address(self):
        self.status.write({
            'latitude': 10.0, 'longitude': 76.0,
            'address': 'MG Road, Kozhikode', 'address_latitude': 10.0, 'address_longitude': 76.0,
        })
        self.assertFalse(self.status._ff_needs_address())

    def test_moving_away_asks_again(self):
        self.status.write({
            'address': 'MG Road, Kozhikode', 'address_latitude': 10.0, 'address_longitude': 76.0,
            'latitude': 10.02, 'longitude': 76.0,  # roughly 2 km away
        })
        self.assertIn(self.status, self.status._ff_needs_address())

    def test_the_address_reads_like_a_place_not_a_postal_essay(self):
        result = {
            'formatted_address': 'XVII/374, Nallalam - Kozhikode Rd, Nallalam, Kozhikode, Kerala 673027, India',
            'address_components': [
                {'long_name': 'Nallalam - Kozhikode Road', 'types': ['route']},
                {'long_name': 'Nallalam', 'types': ['sublocality_level_1', 'sublocality', 'political']},
                {'long_name': 'Kozhikode', 'types': ['locality', 'political']},
                {'long_name': 'Kerala', 'types': ['administrative_area_level_1']},
            ],
        }
        self.assertEqual(self.status._ff_short_address(result),
                         'Nallalam - Kozhikode Road, Nallalam, Kozhikode')

    def test_an_address_with_no_named_parts_falls_back_to_the_full_one(self):
        result = {'formatted_address': '8PGR+5HF, Naranganam, Kerala', 'address_components': []}
        self.assertEqual(self.status._ff_short_address(result), '8PGR+5HF, Naranganam, Kerala')

    def test_addresses_are_free_unless_google_is_chosen_with_a_key(self):
        from odoo.addons.ff_base.tools import geocode_provider
        Param = self.env['ir.config_parameter'].sudo()
        Param.set_param('ff_base.google_maps_key', 'AIza-test')
        self.assertEqual(geocode_provider(self.env), 'open')
        Param.set_param('ff_base.geocode_provider', 'google')
        self.assertEqual(geocode_provider(self.env), 'google')
        Param.set_param('ff_base.google_maps_key', '')
        self.assertEqual(geocode_provider(self.env), 'open')

    def test_the_guard_stops_google_before_the_free_tier_ends(self):
        Param = self.env['ir.config_parameter'].sudo()
        Param.set_param('ff_base.map_free_tiles', 1000)
        self.Usage.ff_record('tiles', 899, employee=self.employee)
        self.assertTrue(self.Usage.ff_google_allowed('tiles'))
        self.Usage.ff_record('tiles', 1, employee=self.employee)  # 90 % reached
        self.assertFalse(self.Usage.ff_google_allowed('tiles'))
        self.assertTrue(self.Usage.ff_google_allowed('web_map'))
        Param.set_param('ff_base.map_free_guard', 'False')
        self.assertTrue(self.Usage.ff_google_allowed('tiles'))

    def test_the_web_map_falls_back_to_free_when_its_loads_are_used(self):
        Param = self.env['ir.config_parameter'].sudo()
        Param.set_param('ff_base.google_maps_key', 'AIza-test')
        Param.set_param('ff_base.map_provider', 'google')
        Param.set_param('ff_base.map_free_loads', 10)
        self.Usage.ff_record('web_map', 9)
        data = self.Status.ff_live_map()
        self.assertEqual(data['map_provider'], 'open')
        self.assertEqual(data['google_maps_key'], '')

    def test_nothing_to_resolve_clears_an_old_warning(self):
        Param = self.env['ir.config_parameter'].sudo()
        Param.set_param('ff_base.google_maps_key', 'AIza-test')
        Param.set_param('ff_base.geocode_problem', 'REQUEST_DENIED')
        self.status.write({'latitude': 0.0, 'longitude': 0.0})  # nothing to look up
        self.status.ff_resolve_addresses()
        self.assertFalse(Param.get_param('ff_base.geocode_problem'))

    def test_an_unreadable_month_falls_back_to_this_one(self):
        summary = self.Usage.ff_usage_summary('NaN-NaN-01')
        self.assertEqual(summary['month'], fields.Date.context_today(self.Usage).strftime('%Y-%m'))

    def test_a_month_can_be_asked_for_by_date(self):
        summary = self.Usage.ff_usage_summary('2026-04-01')
        self.assertEqual(summary['month'], '2026-04')
