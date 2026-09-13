"""FOC in the app: which schemes run, and what a cart earns free."""
from odoo import http
from odoo.http import request

from odoo.addons.ff_mobile_api.controllers.clients import to_int, visible_client
from odoo.addons.ff_mobile_api.controllers.common import api_route, body, ok

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
