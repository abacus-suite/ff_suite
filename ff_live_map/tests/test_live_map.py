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
