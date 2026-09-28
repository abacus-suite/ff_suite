from odoo import fields, http
from odoo.exceptions import UserError
from odoo.http import request

from odoo.addons.ff_base.tools import to_iso

from .common import ApiError, api_route, bearer_token, body, employee_profile, ok


def _device_vals(data):
    return {
        'device_uid': data.get('device_uid'),
        'name': data.get('device_name'),
        'os_version': data.get('os_version'),
        'app_version': data.get('app_version'),
        'fcm_token': data.get('fcm_token'),
    }


class FieldForceAuthApi(http.Controller):

    @api_route('/api/v1/auth/login', methods=('POST',), public=True)
    def login(self, **kw):
        data = body()
        login, password, device_uid = data.get('login'), data.get('password'), data.get('device_uid')
        if not login or not password or not device_uid:
            raise ApiError('login, password and device_uid are required.')
        try:
            employee = request.env['hr.employee'].sudo().ff_app_authenticate(login, password)
        except UserError as e:
            raise ApiError(str(e.args[0]), 429, 'locked')
        if not employee:
            request.env.cr.commit()  # keep the failed-attempt counter despite the error response
            raise ApiError('Invalid login or password.', 401, 'invalid_credentials')
        token, expires_at = request.env['ff.app.token'].ff_issue(employee, device_uid, data.get('device_name'))
        request.env['ff.device'].ff_register(employee, _device_vals(data))
        return ok({
            'token': token,
            'token_type': 'Bearer',
            'expires_at': to_iso(expires_at),
            'profile': employee_profile(employee),
        })

    @api_route('/api/v1/auth/logout', methods=('POST',))
    def logout(self, employee, **kw):
        request.env['ff.app.token'].sudo().ff_resolve(bearer_token()).unlink()
        device_uid = body().get('device_uid')
        if device_uid:
            request.env['ff.device'].sudo().search([
                ('employee_id', '=', employee.id), ('device_uid', '=', device_uid),
            ]).write({'fcm_token': False, 'active': False})
        return ok()

    @api_route('/api/v1/me', methods=('GET',))
    def me(self, employee, **kw):
        return ok(dict(employee_profile(employee), server_time=to_iso(fields.Datetime.now())))

    @api_route('/api/v1/device/register', methods=('POST',))
    def register_device(self, employee, **kw):
        data = body()
        if not data.get('device_uid'):
            raise ApiError('device_uid is required.')
        device = request.env['ff.device'].ff_register(employee, _device_vals(data))
        return ok({'id': device.id})
