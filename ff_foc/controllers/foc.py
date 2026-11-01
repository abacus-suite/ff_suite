"""FOC in the app: which schemes run, and what a cart earns free."""
from odoo import http
from odoo.exceptions import UserError
from odoo.http import request

from odoo.addons.ff_mobile_api.controllers.clients import to_int, visible_client
from odoo.addons.ff_mobile_api.controllers.common import ApiError, api_route, body, ok, ref

from ..models.documents import manual_allowed


class FieldForceFocApi(http.Controller):

    @api_route('/api/v1/foc/schemes', methods=('GET',))
    def schemes(self, employee, partner_id=None, **kw):
        partner = visible_client(employee, to_int(partner_id)) if partner_id else None
        schemes = request.env['ff.foc.scheme'].ff_applicable(employee, partner)
        return ok({'manual_allowed': manual_allowed(request.env), 'schemes': schemes.ff_payload()})

    @api_route('/api/v1/foc/preview', methods=('POST',))
    def preview(self, employee, **kw):
        data = body()
        partner = visible_client(employee, to_int(data.get('partner_id')))
        Product = request.env['product.product'].sudo()
        lines = []
        for row in data.get('lines') or []:
            product = Product.browse(to_int(row.get('product_id')) or []).exists()
            try:
                quantity = float(row.get('qty') or 0)
            except (TypeError, ValueError):
                quantity = 0
            if product and quantity > 0:
                lines.append((product, quantity))
        free = request.env['ff.foc.scheme'].ff_compute(employee, partner, lines)
        return ok([{
            'product': {'id': row['product'].id, 'name': row['product'].display_name},
            'qty': row['quantity'],
            'scheme': {'id': row['scheme'].id, 'name': row['scheme'].name, 'summary': row['scheme'].summary},
            'bought': row['bought'],
            'value': round(row['quantity'] * row['product'].ff_field_price(), 2),
        } for row in free])

    @api_route('/api/v1/demands/<int:demand_id>/foc-request', methods=('POST',))
    def foc_request(self, employee, demand_id, **kw):
        """Ask the distributor to deliver the free goods; no order is made for them."""
        demand = _my_demand(employee, demand_id)
        distributor = request.env['res.partner'].sudo().browse(to_int(body().get('distributor_id')) or 0).exists()
        try:
            sent = demand.ff_foc_request(employee, distributor)
        except UserError as error:
            raise ApiError(str(error), 400, 'invalid')
        return ok({'message': sent['message'], 'phone': sent['phone'],
                   'distributor': ref(sent['distributor']), 'foc_status': demand.foc_status})

    @api_route('/api/v1/demands/<int:demand_id>/foc-delivered', methods=('POST',))
    def foc_delivered(self, employee, demand_id, **kw):
        demand = _my_demand(employee, demand_id)
        try:
            demand.ff_foc_deliver((body().get('note') or '').strip() or None)
        except UserError as error:
            raise ApiError(str(error), 400, 'invalid')
        return ok({'foc_status': demand.foc_status, 'state': demand.state})


def _my_demand(employee, demand_id):
    demand = request.env['ff.demand'].sudo().browse(demand_id).exists()
    if not demand or not (demand.employee_id == employee or demand.employee_id in employee._ff_subordinates()):
        raise ApiError('Demand not found.', 404, 'not_found')
    return demand
