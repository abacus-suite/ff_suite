import inspect
from datetime import timedelta

from odoo import fields, http
from odoo.exceptions import AccessDenied
from odoo.http import request

from odoo.addons.ff_base.tools import to_iso

from .common import ApiError, api_route, body, employee_profile, ok

TOKEN_VALIDITY_DAYS = 90
KEY_PREFIX = 'ff_mobile:'


def _authenticate(credential):
    """Password check through the session, compatible with Odoo 18 and 19."""
    authenticate = request.session.authenticate
    first_param = next(iter(inspect.signature(authenticate).parameters), None)
    target = request.env if first_param == 'env' else request.db
    info = authenticate(target, credential)
    return info['uid'] if isinstance(info, dict) else info


def _device_vals(data):
    return {
        'device_uid': data.get('device_uid'),
        'name': data.get('device_name'),
        'os_version': data.get('os_version'),
        'app_version': data.get('app_version'),
        'fcm_token': data.get('fcm_token'),
    }


class FieldForceAuthApi(http.Controller):

    @api_route('/api/v1/auth/login', methods=('POST',), auth='public')
    def login(self, **kw):
        data = body()
        login, password, device_uid = data.get('login'), data.get('password'), data.get('device_uid')
        if not login or not password or not device_uid:
            raise ApiError('login, password and device_uid are required.')
        try:
            uid = _authenticate({'login': login, 'password': password, 'type': 'password'})
        except AccessDenied:
            raise ApiError('Invalid login or password.', 401, 'invalid_credentials')
        request.session.logout(keep_db=True)  # the app uses the bearer token, not a cookie

        env = request.env(user=uid)
        user = env.user
        if not user.has_group('ff_base.group_ff_officer'):
            raise ApiError('This user has no Field Force access.', 403, 'forbidden')
        employee = user.employee_id.sudo()
        if not employee:
            raise ApiError('No employee is linked to this user.', 403, 'no_employee')

        keys = env['res.users.apikeys'].sudo()
        key_name = KEY_PREFIX + device_uid
        keys.search([('user_id', '=', uid), ('name', '=', key_name)]).unlink()
        expires_at = fields.Datetime.now() + timedelta(days=TOKEN_VALIDITY_DAYS)
        token = keys._generate('rpc', key_name, expires_at)

        env['ff.device'].ff_register(employee, _device_vals(data))
        return ok({
            'token': token,
            'token_type': 'Bearer',
            'expires_at': to_iso(expires_at),
            'profile': employee_profile(employee, user),
        })

    @api_route('/api/v1/auth/logout', methods=('POST',))
    def logout(self, employee, **kw):
        device_uid = body().get('device_uid')
        if device_uid:
            request.env['res.users.apikeys'].sudo().search([
                ('user_id', '=', request.env.uid), ('name', '=', KEY_PREFIX + device_uid),
            ]).unlink()
            request.env['ff.device'].sudo().search([
                ('employee_id', '=', employee.id), ('device_uid', '=', device_uid),
            ]).write({'fcm_token': False, 'active': False})
        return ok()

    @api_route('/api/v1/me', methods=('GET',))
    def me(self, employee, **kw):
        return ok(dict(employee_profile(employee, request.env.user), server_time=to_iso(fields.Datetime.now())))

    @api_route('/api/v1/device/register', methods=('POST',))
    def register_device(self, employee, **kw):
        data = body()
        if not data.get('device_uid'):
            raise ApiError('device_uid is required.')
        device = request.env['ff.device'].ff_register(employee, _device_vals(data))
        return ok({'id': device.id})
