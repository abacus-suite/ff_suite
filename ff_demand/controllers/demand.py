"""Demand endpoints, and the switch that decides what an app order becomes."""
from odoo import fields, http
from odoo.http import request

from odoo.addons.ff_base.tools import to_iso
from odoo.addons.ff_mobile_api.controllers.clients import to_int, visible_client
from odoo.addons.ff_mobile_api.controllers.common import (
    ApiError, action_time, api_route, body, ok, ref, require_punched_in, scope_members)

from ..models.ff_demand import order_flow

STATE_LABELS = {
    'draft': 'Draft',
    'submitted': 'Submitted',
    'quoted': 'Sent to distributor',
    'partial': 'Partly sent',
    'supplied': 'Supplied',
    'cancelled': 'Cancelled',
}


def demand_data(demand, with_lines=False):
    data = {
        'id': demand.id,
        'name': demand.name,
        'kind': 'demand',
        'client': ref(demand.partner_id),
        'employee': ref(demand.employee_id),
        'distributor': ref(demand.distributor_id),
        'date': to_iso(demand.date),
        'amount_total': demand.amount_total,
        'currency': demand.currency_id.name,
        'state': demand.state,
        'state_label': STATE_LABELS.get(demand.state, demand.state),
        'quoted_percent': demand.quoted_ratio,
        'note': demand.note or None,
        'route': ref(demand.route_id),
    }
    if with_lines == 'brief':
        # Just enough for grouping by product in the list.
        data['products'] = [{'id': line.product_id.id, 'name': line.product_id.display_name,
                             'qty': line.quantity, 'subtotal': line.subtotal}
                            for line in demand.line_ids if line.product_id]
    elif with_lines:
        data['lines'] = [{
            'product': ref(line.product_id),
            'sku': line.product_id.product_tmpl_id.ff_sku_code or None,
            'qty': line.quantity,
            'quoted_qty': line.quoted_quantity,
            'price_unit': line.price_unit,
            'subtotal': line.subtotal,
            'foc': bool(getattr(line, 'is_foc', False)),
            'foc_note': (line.foc_scheme_id.name or line.foc_reason or None) if getattr(line, 'is_foc', False) else None,
        } for line in demand.line_ids]
    return data


class FieldForceDemandApi(http.Controller):

    @api_route('/api/v1/demands', methods=('POST',))
    def create_demand(self, employee, **kw):
        data = body()
        partner = visible_client(employee, to_int(data.get('partner_id')))
        require_punched_in(employee, 'add a demand', data)
        request.env['ff.visit'].ff_require_visit(employee, partner, action_time(data) if data.get('at') else None)
        demand = request.env['ff.demand'].ff_create_from_app(employee, partner, data)
        return ok(demand_data(demand, with_lines=True), status=201)

    @api_route('/api/v1/demands', methods=('GET',))
    def demands(self, employee, partner_id=None, limit=None, member=None, start=None, end=None,
                state=None, q=None, route_id=None, **kw):
        people, _label = scope_members(employee, member)
        domain = [('employee_id', 'in', people.ids)]
        if partner_id:
            domain.append(('partner_id', '=', to_int(partner_id)))
        if route_id:
            domain.append(('route_id', '=', to_int(route_id)))
        if state:
            domain.append(('state', 'in', state.split(',')))
        if q:
            domain += ['|', '|', ('name', 'ilike', q), ('partner_id.name', 'ilike', q),
                       ('line_ids.product_id.name', 'ilike', q)]
        if start or end:
            try:
                low_day = fields.Date.to_date(start) if start else fields.Date.to_date(end)
                high_day = fields.Date.to_date(end) if end else low_day
            except ValueError:
                raise ApiError('Dates must be YYYY-MM-DD.')
            domain += [('date', '>=', employee._ff_day_bounds(min(low_day, high_day))[0]),
                       ('date', '<', employee._ff_day_bounds(max(low_day, high_day))[1])]
        demands = request.env['ff.demand'].sudo().search(
            domain, order='date desc', limit=min(to_int(limit) or 200, 1000))
        return ok([demand_data(demand, with_lines='brief') for demand in demands])

    @api_route('/api/v1/demands/<int:demand_id>', methods=('GET',))
    def demand(self, employee, demand_id, **kw):
        demand = request.env['ff.demand'].sudo().browse(demand_id).exists()
        allowed = demand and (demand.employee_id == employee
                              or demand.employee_id in employee._ff_subordinates())
        if not allowed:
            raise ApiError('Demand not found.', 404, 'not_found')
        return ok(demand_data(demand, with_lines=True))

    @api_route('/api/v1/order-flow', methods=('GET',))
    def flow(self, employee, **kw):
        """The app asks once at login which document its orders become."""
        return ok({'flow': order_flow(request.env)})
