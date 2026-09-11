import json

from odoo.tests import HttpCase, new_test_user, tagged

PASSWORD = 'Field#Officer2026'


@tagged('post_install', '-at_install', 'ff')
class TestMobileApi(HttpCase):

    @classmethod
    def setUpClass(cls):
        super().setUpClass()
        cls.env['ir.config_parameter'].sudo().set_param('ff_base.selfie_required', 'False')
        cls.manager_user = new_test_user(cls.env, login='ff_api_manager', password=PASSWORD,
                                         groups='base.group_user,ff_base.group_ff_manager')
        cls.manager = cls.env['hr.employee'].create({'name': 'API Manager', 'user_id': cls.manager_user.id})
        cls.officer_user = new_test_user(cls.env, login='ff_api_officer', password=PASSWORD,
                                         groups='base.group_user,ff_base.group_ff_officer')
        cls.officer = cls.env['hr.employee'].create({
            'name': 'API Officer', 'user_id': cls.officer_user.id, 'parent_id': cls.manager.id, 'tz': 'Asia/Kolkata',
        })

    def _call(self, url, payload=None, token=None):
        headers = {'Content-Type': 'application/json'}
        if token:
            headers['Authorization'] = 'Bearer %s' % token
        if payload is None:
            return self.url_open(url, headers=headers)
        return self.url_open(url, data=json.dumps(payload), headers=headers)

    def _login(self, login, device='device-1'):
        res = self._call('/api/v1/auth/login', {'login': login, 'password': PASSWORD, 'device_uid': device})
        self.assertEqual(res.status_code, 200, res.text)
        return res.json()['data']['token']

    def test_login_errors(self):
        res = self._call('/api/v1/auth/login', {'login': 'ff_api_officer', 'password': 'wrong', 'device_uid': 'd'})
        self.assertEqual(res.status_code, 401, res.text)
        res = self._call('/api/v1/auth/login', {'login': 'ff_api_officer'})
        self.assertEqual(res.status_code, 400, res.text)

    def test_officer_flow(self):
        token = self._login('ff_api_officer')
        me = self._call('/api/v1/me', token=token)
        self.assertEqual(me.status_code, 200, me.text)
        self.assertEqual(me.json()['data']['employee']['id'], self.officer.id)
        self.assertFalse(me.json()['data']['roles']['is_manager'])

        punch = self._call('/api/v1/attendance/punch-in', {'lat': 10.0, 'lng': 76.0, 'accuracy': 5}, token)
        self.assertEqual(punch.status_code, 200, punch.text)
        again = self._call('/api/v1/attendance/punch-in', {'lat': 10.0, 'lng': 76.0}, token)
        self.assertEqual(again.status_code, 400, again.text)

        pings = self._call('/api/v1/tracking/pings', {'pings': [
            {'uuid': 'api-1', 'lat': 10.001, 'lng': 76.0, 'battery': 80},
        ]}, token)
        self.assertEqual(pings.json()['data']['accepted'], 1, pings.text)

        status = self._call('/api/v1/attendance/status', token=token)
        self.assertTrue(status.json()['data']['punched_in'], status.text)

        month = self._call('/api/v1/attendance/month', token=token)
        self.assertEqual(month.status_code, 200, month.text)

        forbidden = self._call('/api/v1/team/live', token=token)
        self.assertEqual(forbidden.status_code, 403, forbidden.text)

    def test_manager_flow(self):
        self.env['ff.location.ping'].ff_ingest(self.officer, [{'uuid': 'mgr-1', 'lat': 10.0, 'lng': 76.0}])
        token = self._login('ff_api_manager', device='device-2')
        live = self._call('/api/v1/team/live', token=token)
        self.assertEqual(live.status_code, 200, live.text)
        ids = [m['employee']['id'] for m in live.json()['data']['members']]
        self.assertIn(self.officer.id, ids)

        timeline = self._call('/api/v1/team/%s/timeline' % self.officer.id, token=token)
        self.assertEqual(timeline.status_code, 200, timeline.text)
        self.assertEqual(len(timeline.json()['data']['points']), 1)
