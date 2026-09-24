"""Returns and damaged stock from the app."""
from odoo import http
from odoo.http import request

from odoo.addons.ff_mobile_api.controllers.clients import to_int, visible_client
from odoo.addons.ff_mobile_api.controllers.common import (
    ApiError, action_time, api_route, body, ok, require_punched_in)

from ..models.ff_return import REASONS


class FieldForceReturnsApi(http.Controller):

    @api_route('/api/v1/returns/reasons', methods=('GET',))
    def reasons(self, employee, **kw):
        return ok([{'key': key, 'label': label} for key, label in REASONS])

    @api_route('/api/v1/returns', methods=('GET',))
    def my_returns(self, employee, partner_id=None, **kw):
        domain = [('employee_id', '=', employee.id)]
        if partner_id:
            domain.append(('partner_id', '=', to_int(partner_id)))
        records = request.env['ff.return'].sudo().search(domain, limit=100)
        return ok([record.ff_payload() for record in records])

    @api_route('/api/v1/returns', methods=('POST',))
    def create(self, employee, **kw):
        data = body()
        partner = visible_client(employee, to_int(data.get('partner_id')))
        require_punched_in(employee, 'record a return', data)
        request.env['ff.visit'].ff_require_visit(employee, partner, action_time(data) if data.get('at') else None)
        record = request.env['ff.return'].ff_create_from_app(employee, partner, data)
        return ok(record.ff_payload(), status=201)

    @api_route('/api/v1/returns/to-approve', methods=('GET',), manager=True)
    def to_approve(self, employee, **kw):
        records = request.env['ff.return'].sudo().search([
            ('employee_id', 'in', employee._ff_subordinates().ids), ('state', '=', 'submitted')], limit=100)
        return ok([record.ff_payload() for record in records])

    @api_route('/api/v1/returns/<int:return_id>/<string:decision>', methods=('POST',), manager=True)
    def decide(self, employee, return_id, decision, **kw):
        if decision not in ('approve', 'reject'):
            raise ApiError('decision must be "approve" or "reject".')
        record = request.env['ff.return'].sudo().browse(return_id).exists()
        if not record:
            raise ApiError('Return not found.', 404, 'not_found')
        return ok(record.ff_decide_as(employee, decision == 'approve').ff_payload())
