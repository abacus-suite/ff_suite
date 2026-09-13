import math

from odoo import http
from odoo.http import request

from .common import ApiError, api_route, body, ok, ref
from .field_data import client_data, visit_data

MAX_LIMIT = 200
DEFAULT_RADIUS_KM = 25.0


def to_float(value):
    try:
        return float(value)
    except (TypeError, ValueError):
        return None


def to_int(value):
    try:
        return int(value)
    except (TypeError, ValueError):
        return None


def client_domain(employee):
    if employee.ff_access_scope == 'all':
        return [('ff_is_client', '=', True), ('ff_approval_state', '!=', 'rejected')]
    return request.env['res.partner']._ff_visible_domain(employee)


def visible_client(employee, partner_id):
    partner = request.env['res.partner'].sudo().search(client_domain(employee) + [('id', '=', partner_id)], limit=1)
    if not partner:
        raise ApiError('Client not found.', 404, 'not_found')
    return partner


def category_for(employee, category_id):
    """Contact category chosen in the app, restricted to the employee's department."""
    allowed = request.env['ff.contact.category'].ff_for_employee(employee)
    if category_id:
        category = allowed.filtered(lambda c: c.id == to_int(category_id))
        if not category:
            raise ApiError('You do not have access to this contact category.', 403, 'forbidden')
        return category
    if len(allowed) == 1:
        return allowed
    raise ApiError('category_id is required: choose a contact category.')


class FieldForceClientsApi(http.Controller):

    @api_route('/api/v1/clients', methods=('GET',))
    def clients(self, employee, q=None, category_id=None, lat=None, lng=None, radius_km=None,
                limit=None, offset=None, **kw):
        Partner = request.env['res.partner'].sudo()
        domain = client_domain(employee)
        if q:
            domain += ['|', '|', '|', ('name', 'ilike', q), ('ff_client_code', 'ilike', q),
                       ('phone', 'ilike', q), ('city', 'ilike', q)]
        if category_id:
            domain.append(('ff_category_id', '=', to_int(category_id)))
        try:
            limit = min(int(limit or 50), MAX_LIMIT)
            offset = max(int(offset or 0), 0)
        except ValueError:
            raise ApiError('limit and offset must be numbers.')
        lat, lng = to_float(lat), to_float(lng)

        if lat is not None and lng is not None:
            radius = to_float(radius_km) or DEFAULT_RADIUS_KM
            dlat = radius / 111.0
            dlng = dlat / max(math.cos(math.radians(lat)), 0.2)
            domain += [('partner_latitude', '>=', lat - dlat), ('partner_latitude', '<=', lat + dlat),
                       ('partner_longitude', '>=', lng - dlng), ('partner_longitude', '<=', lng + dlng)]
            rows = [client_data(p, lat, lng) for p in Partner.search(domain)]
            rows = sorted((r for r in rows if r['distance_m'] <= radius * 1000), key=lambda r: r['distance_m'])
            return ok({'total': len(rows), 'clients': rows[offset:offset + limit]})

        total = Partner.search_count(domain)
        partners = Partner.search(domain, order='name', limit=limit, offset=offset)
        return ok({'total': total, 'clients': [client_data(p) for p in partners]})

    @api_route('/api/v1/clients/<int:partner_id>', methods=('GET',))
    def client(self, employee, partner_id, lat=None, lng=None, **kw):
        partner = visible_client(employee, partner_id)
        visits = request.env['ff.visit'].sudo().search([('partner_id', '=', partner.id)], limit=5)
        sites = partner.child_ids.filtered(lambda c: c.ff_is_client and c.ff_approval_state == 'approved')
        data = client_data(partner, to_float(lat), to_float(lng))
        data.update(
            sites=[client_data(s) for s in sites],
            recent_visits=[visit_data(v) for v in visits],
            allow_orders=bool(partner.ff_category_id.allow_orders),
        )
        return ok(data)

    @api_route('/api/v1/clients', methods=('POST',))
    def create_client(self, employee, **kw):
        data = body()
        name = (data.get('name') or '').strip()
        if not name:
            raise ApiError('Client name is required.')
        vals = {
            'name': name,
            'phone': data.get('phone') or False,
            'email': data.get('email') or False,
            'street': data.get('street') or False,
            'city': data.get('city') or False,
            'zip': data.get('zip') or False,
            'comment': data.get('note') or False,
            'partner_latitude': to_float(data.get('lat')) or 0.0,
            'partner_longitude': to_float(data.get('lng')) or 0.0,
            'ff_category_id': category_for(employee, data.get('category_id')).id,
            'ff_district_id': to_int(data.get('district_id')) or False,
        }
        if data.get('parent_id'):
            vals.update(parent_id=visible_client(employee, int(data['parent_id'])).id, type='other')
        if data.get('route_id'):
            route = request.env['ff.beat'].sudo().browse(to_int(data['route_id']) or []).exists()
            if not route or (employee.ff_route_ids and route not in employee.ff_route_ids):
                raise ApiError('This route is not assigned to you.', 403, 'forbidden')
            # The contact joins the route and is shared with everyone working it.
            vals['ff_route_ids'] = [(4, route.id)]
            vals['ff_extra_employee_ids'] = route.employee_ids.ids
            # A route covers one city: the customer takes it unless the app said otherwise.
            if route.district_id and not vals.get('ff_district_id'):
                vals['ff_district_id'] = route.district_id.id
            if route.district_id and not vals.get('city'):
                vals['city'] = route.district_id.name
            if route.state_id and not vals.get('state_id'):
                vals['state_id'] = route.state_id.id
            if route.country_id and not vals.get('country_id'):
                vals['country_id'] = route.country_id.id
        partner = request.env['res.partner'].ff_create_from_app(employee, vals)
        return ok(client_data(partner), status=201)

    @api_route('/api/v1/contact-categories', methods=('GET',))
    def contact_categories(self, employee, **kw):
        categories = request.env['ff.contact.category'].ff_for_employee(employee)
        return ok([{
            'id': c.id,
            'name': c.name,
            'type': c.category_type,
            'allow_orders': c.allow_orders,
            'requires_approval': c.requires_approval,
        } for c in categories])

    @api_route('/api/v1/districts', methods=('GET',))
    def districts(self, employee, state_id=None, q=None, **kw):
        domain = []
        if state_id:
            domain.append(('state_id', '=', to_int(state_id)))
        if q:
            domain.append(('name', 'ilike', q))
        districts = request.env['ff.district'].sudo().search(domain, limit=200)
        return ok([{'id': d.id, 'name': d.name, 'state': ref(d.state_id), 'country': ref(d.country_id)}
                   for d in districts])
