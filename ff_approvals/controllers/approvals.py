"""Approval queue and notifications for the Field Force app."""
from odoo import http
from odoo.http import request

from odoo.addons.ff_base.tools import to_iso
from odoo.addons.ff_mobile_api.controllers.clients import to_int
from odoo.addons.ff_mobile_api.controllers.common import ApiError, api_route, body, ok, ref


def line_data(line):
    return {
        'step': line.name,
        'approver': ref(line.user_id.employee_id) if line.user_id else None,
        'approver_name': line.user_id.name or '',
        'state': line.state,
        'decided_at': to_iso(line.decided_at),
        'note': line.note or None,
    }


class FieldForceApprovalApi(http.Controller):

    @api_route('/api/v1/notifications', methods=('GET',))
    def notifications(self, employee, unread=None, limit=None, **kw):
        rows = request.env['ff.notification'].ff_for(
            employee, unread_only=unread in ('1', 'true', 'True'), limit=min(to_int(limit) or 50, 200))
        unread_count = request.env['ff.notification'].sudo().search_count([
            ('employee_id', '=', employee.id), ('read_at', '=', False)])
        return ok({'unread': unread_count, 'notifications': [row.ff_payload() for row in rows]})

    @api_route('/api/v1/notifications/read', methods=('POST',))
    def mark_read(self, employee, **kw):
        ids = body().get('ids') or []
        Notification = request.env['ff.notification'].sudo()
        rows = (Notification.browse([int(i) for i in ids]) if ids
                else Notification.search([('employee_id', '=', employee.id), ('read_at', '=', False)]))
        rows.filtered(lambda row: row.employee_id == employee).ff_mark_read()
        return ok({'read': True})

    @api_route('/api/v1/approvals/chain/<string:model>/<int:doc_id>', methods=('GET',))
    def chain(self, employee, model, doc_id, **kw):
        """Who has signed this document, and who it is waiting for."""
        if model not in ('expense', 'allowance'):
            raise ApiError('Unknown document.', 404, 'not_found')
        record_model = 'ff.expense.claim' if model == 'expense' else 'ff.allowance.claim'
        document = request.env[record_model].sudo().browse(doc_id).exists()
        if not document or (document.employee_id != employee
                            and document.employee_id not in employee._ff_subordinates()):
            raise ApiError('Document not found.', 404, 'not_found')
        lines = document.approval_line_ids.sorted('sequence')
        return ok({
            'document': document.display_name,
            'state': document.state,
            'waiting_for': document.approver_user_id.name or None,
            'steps': [line_data(line) for line in lines],
        })
