"""Credit and debit notes a manager decides from the app."""
from odoo import http
from odoo.http import request

from odoo.addons.ff_mobile_api.controllers.common import ApiError, api_route, note_rejection, ok


class FieldForceNotesApi(http.Controller):

    @api_route('/api/v1/notes/to-approve', methods=('GET',), manager=True)
    def to_approve(self, employee, **kw):
        notes = request.env['ff.distributor.note'].sudo().search([
            ('employee_id', 'in', employee._ff_subordinates().ids), ('state', '=', 'pending')], limit=200)
        return ok([n.ff_approval_payload() for n in notes])

    @api_route('/api/v1/notes/<int:note_id>/<string:decision>', methods=('POST',), manager=True)
    def decide(self, employee, note_id, decision, **kw):
        if decision not in ('approve', 'reject'):
            raise ApiError('decision must be "approve" or "reject".')
        note = request.env['ff.distributor.note'].sudo().browse(note_id).exists()
        if not note:
            raise ApiError('Note not found.', 404, 'not_found')
        note.ff_decide_as(employee, decision == 'approve')
        note_rejection(note, decision == 'approve', employee)
        return ok(note.ff_approval_payload())
