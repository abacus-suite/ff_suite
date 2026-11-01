from datetime import timedelta

from odoo import fields
from odoo.exceptions import AccessError, UserError
from odoo.tests import TransactionCase, tagged


@tagged('post_install', '-at_install', 'ff')
class TestAppLeaves(TransactionCase):
    """Asking for time off from the phone, and deciding on it there."""

    @classmethod
    def setUpClass(cls):
        super().setUpClass()
        cls.manager = cls.env['hr.employee'].create({'name': 'Leave Manager', 'ff_access_scope': 'hierarchy'})
        cls.officer = cls.env['hr.employee'].create({'name': 'Leave Officer', 'parent_id': cls.manager.id})
        cls.leave_type = cls.env['hr.leave.type'].create({
            'name': 'Field Casual Leave',
            'requires_allocation': 'no',
            'request_unit': 'day',
        })
        cls.Leave = cls.env['hr.leave']
        cls.tomorrow = fields.Date.context_today(cls.officer) + timedelta(days=1)

    def _request(self, days=1, reason='Family function'):
        return self.Leave.ff_request_from_app(self.officer, {
            'type_id': self.leave_type.id,
            'from': self.tomorrow.isoformat(),
            'to': (self.tomorrow + timedelta(days=days - 1)).isoformat(),
            'reason': reason,
        })

    def test_a_request_from_the_app_waits_for_approval(self):
        leave = self._request()
        payload = leave.ff_app_payload()
        self.assertEqual(payload['type']['name'], 'Field Casual Leave')
        self.assertEqual(payload['state_label'], 'Waiting approval')
        self.assertTrue(payload['can_cancel'])

    def test_the_types_say_what_is_left(self):
        rows = self.Leave.ff_types_for(self.officer)
        names = [row['name'] for row in rows]
        self.assertIn('Field Casual Leave', names)
        self.assertIn('remaining', rows[0])

    def test_dates_the_wrong_way_round_are_turned_around(self):
        leave = self.Leave.ff_request_from_app(self.officer, {
            'type_id': self.leave_type.id,
            'from': (self.tomorrow + timedelta(days=3)).isoformat(),
            'to': self.tomorrow.isoformat(),
        })
        self.assertEqual(leave.request_date_from, self.tomorrow)

    def test_a_request_without_a_type_is_refused(self):
        with self.assertRaises(UserError):
            self.Leave.ff_request_from_app(self.officer, {'from': self.tomorrow.isoformat()})

    def test_the_manager_sees_it_waiting_and_can_approve(self):
        leave = self._request()
        waiting = self.Leave.ff_to_approve(self.manager)
        self.assertIn(leave.id, [row['id'] for row in waiting])
        leave.ff_decide_as(self.manager, True)
        self.assertEqual(leave.state, 'validate')

    def test_somebody_else_cannot_decide(self):
        leave = self._request()
        stranger = self.env['hr.employee'].create({'name': 'Not The Manager'})
        with self.assertRaises(AccessError):
            leave.ff_decide_as(stranger, True)

    def test_only_my_own_waiting_request_can_be_withdrawn(self):
        leave = self._request()
        with self.assertRaises(AccessError):
            leave.ff_cancel_as(self.manager)
        self.assertTrue(leave.ff_cancel_as(self.officer))
