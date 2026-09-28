"""The employee's own photo, shown on their profile and the Home screen."""
import base64
import hashlib

from odoo import http
from odoo.http import request

from .clients import to_int
from .common import ApiError, api_route, body, ok

MAX_BYTES = 3 * 1024 * 1024


def photo_version(employee):
    """Changes whenever the photo does, so the app knows to fetch it again."""
    raw = employee.sudo().image_128
    return hashlib.sha1(raw).hexdigest()[:12] if raw else None


class FieldForceProfileApi(http.Controller):

    @api_route('/api/v1/me/photo', methods=('GET',))
    def my_photo(self, employee, size=None, **kw):
        return self._photo(employee, size)

    @api_route('/api/v1/employees/<int:employee_id>/photo', methods=('GET',))
    def employee_photo(self, employee, employee_id, size=None, **kw):
        target = request.env['hr.employee'].sudo().browse(employee_id).exists()
        if not target or (target != employee and target not in employee._ff_subordinates()
                          and target != employee.parent_id):
            raise ApiError('Employee not found.', 404, 'not_found')
        return self._photo(target, size)

    def _photo(self, employee, size):
        field = {'128': 'image_128', '512': 'image_512'}.get(str(to_int(size) or ''), 'image_512')
        data = employee.sudo()[field]
        if not data:
            raise ApiError('No photo yet.', 404, 'not_found')
        raw = base64.b64decode(data)  # image fields are read as base64
        mime = 'image/png' if raw[:4] == b'\x89PNG' else 'image/jpeg'
        return request.make_response(raw, headers=[('Content-Type', mime), ('Cache-Control', 'private, max-age=86400')])

    @api_route('/api/v1/me/photo', methods=('POST',))
    def set_photo(self, employee, **kw):
        image = body().get('image') or ''
        if ',' in image[:80]:
            image = image.split(',', 1)[1]
        try:
            raw = base64.b64decode(image, validate=True)
        except ValueError:
            raise ApiError('The photo could not be read.')
        if not raw or len(raw) > MAX_BYTES:
            raise ApiError('Choose a photo under 3 MB.')
        employee.sudo().write({'image_1920': base64.b64encode(raw)})
        employee.sudo().message_post(body='Profile photo changed from the app.')
        return ok({'photo_version': photo_version(employee)})
