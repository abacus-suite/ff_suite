"""The pictures and documents uploaded with a request, for the manager who decides on it."""
import base64

from odoo import http
from odoo.http import request

from .common import ApiError, api_route, ok

# The requests that carry uploaded pictures. The person asking must be the employee it is about, or a manager of them.
MODELS = ('ff.expense.claim', 'ff.expense.request', 'ff.return', 'ff.collection', 'ff.allowance.claim', 'ff.da.claim',
          'ff.regularisation', 'hr.leave', 'ff.distributor.note')


def _owner(record):
    for name in ('employee_id', 'ff_employee_id'):
        if name in record._fields and record[name]:
            return record[name]
    return None


def _may_see(employee, record):
    user = employee.sudo().user_id
    if user and user.has_group('ff_base.group_ff_admin'):
        return True
    owner = _owner(record)
    return bool(owner and (owner == employee or employee._ff_is_manager_of(owner)))


class FieldForceDocumentsApi(http.Controller):

    @api_route('/api/v1/documents', methods=('GET',))
    def listing(self, employee, model=None, id=None, **kw):
        """The uploaded files of one request: ``[{id, name, image}]``."""
        if model not in MODELS or model not in request.env:
            raise ApiError('Nothing to show.', 404, 'not_found')
        try:
            record = request.env[model].sudo().browse(int(id)).exists()
        except (TypeError, ValueError):
            raise ApiError('id must be a number.')
        if not record or not _may_see(employee, record):
            raise ApiError('Not found.', 404, 'not_found')
        files = request.env['ir.attachment'].sudo().search([('res_model', '=', model), ('res_id', '=', record.id)])
        return ok([{'id': f.id, 'name': f.name, 'mimetype': f.mimetype or None,
                    'image': bool((f.mimetype or '').startswith('image/'))} for f in files])

    @api_route('/api/v1/documents/<int:attachment_id>/file', methods=('GET',))
    def file(self, employee, attachment_id, **kw):
        attachment = request.env['ir.attachment'].sudo().browse(attachment_id).exists()
        if (not attachment or attachment.res_model not in MODELS or attachment.res_model not in request.env
                or not attachment.res_id):
            raise ApiError('Not found.', 404, 'not_found')
        record = request.env[attachment.res_model].sudo().browse(attachment.res_id).exists()
        if not record or not _may_see(employee, record):
            raise ApiError('Not found.', 404, 'not_found')
        data = attachment.raw or base64.b64decode(attachment.datas or b'')
        return request.make_response(data, headers=[
            ('Content-Type', attachment.mimetype or 'application/octet-stream'),
            ('Content-Length', str(len(data))), ('Cache-Control', 'private, max-age=3600'),
            ('Content-Disposition', 'attachment; filename="%s"' % (attachment.name or 'file').replace('"', ''))])
