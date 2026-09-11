import math

from odoo import http
from odoo.http import request

from .common import ApiError, api_route, body, ok
from .field_data import client_data, visit_data

MAX_LIMIT = 200
DEFAULT_RADIUS_KM = 25.0


def to_float(value):
    try:
        return float(value)
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


class FieldForceClientsApi(http.Controller):

    @api_route('/api/v1/clients', methods=('GET',))
    def clients(self, employee, q=None, lat=None, lng=None, radius_km=None, limit=None, offset=None, **kw):
        Partner = request.env['res.partner'].sudo()
        domain = client_domain(employee)
        if q:
            domain += ['|', '|', '|', ('name', 'ilike', q), ('ff_client_code', 'ilike', q),
                       ('phone', 'ilike', q), ('city', 'ilike', q)]
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
        }
        if data.get('parent_id'):
            vals.update(parent_id=visible_client(employee, int(data['parent_id'])).id, type='other')
        partner = request.env['res.partner'].ff_create_from_app(employee, vals)
        return ok(client_data(partner), status=201)
