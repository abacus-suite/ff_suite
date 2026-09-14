import json

from odoo.tests import HttpCase, tagged

PASSWORD = 'FieldForce#2026'


@tagged('post_install', '-at_install', 'ff')
class TestMobileApi(HttpCase):
    """App login uses the employee's own credentials - no Odoo user needed."""

    @classmethod
    def setUpClass(cls):
        super().setUpClass()
        cls.env['ir.config_parameter'].sudo().set_param('ff_base.selfie_required', 'False')
        Employee = cls.env['hr.employee']
        cls.manager = Employee.create({
            'name': 'API Manager', 'ff_app_access': True, 'ff_app_login': 'Manager@Test',
            'ff_access_scope': 'hierarchy',
        })
        cls.officer = Employee.create({
            'name': 'API Officer', 'parent_id': cls.manager.id, 'tz': 'Asia/Kolkata',
            'ff_app_access': True, 'ff_app_login': 'officer@test',
        })
        cls.outsider = Employee.create({'name': 'Other Team', 'ff_app_access': True, 'ff_app_login': 'other@test'})
        for employee in (cls.manager, cls.officer, cls.outsider):
            employee.ff_set_app_password(PASSWORD)

    def _call(self, url, payload=None, token=None):
        headers = {'Content-Type': 'application/json'}
        if token:
            headers['Authorization'] = 'Bearer %s' % token
        if payload is None:
            return self.url_open(url, headers=headers)
        return self.url_open(url, data=json.dumps(payload), headers=headers)

    def _login(self, login, device='device-1', password=PASSWORD):
        return self._call('/api/v1/auth/login', {'login': login, 'password': password, 'device_uid': device})

    def _token(self, login, device='device-1'):
        res = self._login(login, device)
        self.assertEqual(res.status_code, 200, res.text)
        return res.json()['data']['token']

    def test_login_errors_and_app_access(self):
        self.assertEqual(self._login('officer@test', password='wrong').status_code, 401)
        self.assertEqual(self._call('/api/v1/auth/login', {'login': 'officer@test'}).status_code, 400)
        self.outsider.ff_app_access = False
        self.assertEqual(self._login('other@test').status_code, 401)

    def test_lockout_after_failed_attempts(self):
        for _i in range(8):
            self._login('officer@test', password='wrong')
        self.assertEqual(self._login('officer@test').status_code, 429)

    def test_officer_flow(self):
        token = self._token('OFFICER@test')  # login is case-insensitive
        me = self._call('/api/v1/me', token=token)
        self.assertEqual(me.status_code, 200, me.text)
        self.assertEqual(me.json()['data']['employee']['id'], self.officer.id)
        self.assertFalse(me.json()['data']['roles']['is_manager'])

        punch = self._call('/api/v1/attendance/punch-in', {'lat': 10.0, 'lng': 76.0, 'accuracy': 5}, token)
        self.assertEqual(punch.status_code, 200, punch.text)
        self.assertEqual(self._call('/api/v1/attendance/punch-in', {'lat': 10.0, 'lng': 76.0}, token).status_code, 400)

        pings = self._call('/api/v1/tracking/pings', {'pings': [
            {'uuid': 'api-1', 'lat': 10.001, 'lng': 76.0, 'battery': 80},
        ]}, token)
        self.assertEqual(pings.json()['data']['accepted'], 1, pings.text)
        self.assertTrue(self._call('/api/v1/attendance/status', token=token).json()['data']['punched_in'])
        self.assertEqual(self._call('/api/v1/team/live', token=token).status_code, 403)

    def test_manager_sees_only_scope(self):
        self.env['ff.location.ping'].ff_ingest(self.officer, [{'uuid': 'mgr-1', 'lat': 10.0, 'lng': 76.0}])
        token = self._token('manager@test', device='device-2')
        live = self._call('/api/v1/team/live', token=token)
        self.assertEqual(live.status_code, 200, live.text)
        ids = [m['employee']['id'] for m in live.json()['data']['members']]
        self.assertIn(self.officer.id, ids)
        self.assertNotIn(self.outsider.id, ids)
        self.assertEqual(self._call('/api/v1/team/%s/timeline' % self.officer.id, token=token).status_code, 200)
        self.assertEqual(self._call('/api/v1/team/%s/timeline' % self.outsider.id, token=token).status_code, 404)

    def test_logout_revokes_session(self):
        token = self._token('officer@test')
        self.assertEqual(self._call('/api/v1/auth/logout', {'device_uid': 'device-1'}, token).status_code, 200)
        self.assertEqual(self._call('/api/v1/me', token=token).status_code, 401)
