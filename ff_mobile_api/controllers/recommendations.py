"""Where to go next: today's planned customers in the shortest order, and good stops nearby.

Planned stops are ordered by nearest-neighbour from where the person is now,
then improved with 2-opt, so the list reads as a route. Unplanned suggestions
are customers close by that are due a visit. The whole feature is off unless
"Visit Recommendations" is ticked in Field Force settings.
"""
import math

from odoo import http
from odoo.http import request

from odoo.addons.ff_base.tools import get_param, haversine_m

from .clients import client_domain, to_float
from .common import ApiError, api_route, ok
from .field_data import client_data


def _km(a, b):
    return haversine_m(a[0], a[1], b[0], b[1]) / 1000.0


def _route(start, stops):
    """Order stops for a short path from start (open path, no return)."""
    remaining = list(stops)
    order, here = [], start
    while remaining:
        nearest = min(remaining, key=lambda s: _km(here, s['point']))
        order.append(nearest)
        remaining.remove(nearest)
        here = nearest['point']
    # 2-opt: reverse any segment that shortens the path.
    improved = len(order) > 3
    while improved:
        improved = False
        for i in range(len(order) - 1):
            for j in range(i + 1, len(order)):
                before = order[i - 1]['point'] if i else start
                after = order[j + 1]['point'] if j + 1 < len(order) else None
                old = _km(before, order[i]['point']) + (_km(order[j]['point'], after) if after else 0)
                new = _km(before, order[j]['point']) + (_km(order[i]['point'], after) if after else 0)
                if new + 1e-9 < old:
                    order[i:j + 1] = reversed(order[i:j + 1])
                    improved = True
    return order


class FieldForceRecommendationsApi(http.Controller):

    @api_route('/api/v1/recommendations', methods=('GET',))
    def recommendations(self, employee, lat=None, lng=None, radius_km=None, **kw):
        if not get_param(request.env, 'visit_recommendations'):
            return ok({'enabled': False, 'planned': [], 'nearby': []})
        lat, lng = to_float(lat), to_float(lng)
        if lat is None or lng is None:
            raise ApiError('Current location (lat, lng) is needed for recommendations.')
        here = (lat, lng)
        radius = to_float(radius_km) or float(get_param(request.env, 'recommend_radius_km'))
        due_days = get_param(request.env, 'recommend_due_days')
        today = employee._ff_today()

        # Planned for today and not visited yet
        planned_ids = set()
        planned = []
        plans = request.env['ff.beat.plan'].sudo().search([('employee_id', '=', employee.id), ('date', '=', today)])
        for line in plans.mapped('customer_line_ids'):
            partner = line.partner_id
            planned_ids.add(partner.id)
            if not line.selected or line.cancelled or line.visit_id:
                continue
            if not (partner.partner_latitude or partner.partner_longitude):
                continue
            planned.append({'partner': partner, 'point': (partner.partner_latitude, partner.partner_longitude),
                            'route': line.day_id.beat_id.display_name})
        ordered = _route(here, planned)
        planned_rows, prev, total = [], here, 0.0
        for index, stop in enumerate(ordered, start=1):
            leg = _km(prev, stop['point'])
            total += leg
            row = client_data(stop['partner'], lat, lng)
            row.update(sequence=index, leg_km=round(leg, 2), route=stop['route'])
            planned_rows.append(row)
            prev = stop['point']

        # Unplanned customers close by that are due a visit
        box = radius / 111.0
        Partner = request.env['res.partner'].sudo()
        candidates = Partner.search(client_domain(employee) + [
            ('ff_approval_state', '=', 'approved'),
            ('partner_latitude', '>=', lat - box), ('partner_latitude', '<=', lat + box),
            ('partner_longitude', '>=', lng - box / max(math.cos(math.radians(lat)), 0.2)),
            ('partner_longitude', '<=', lng + box / max(math.cos(math.radians(lat)), 0.2)),
        ], limit=300)
        nearby = []
        for partner in candidates:
            if partner.id in planned_ids:
                continue
            distance = _km(here, (partner.partner_latitude, partner.partner_longitude))
            if distance > radius:
                continue
            days = partner.ff_days_since_visit if partner.ff_days_since_visit >= 0 else None
            if days is not None and days < due_days:
                continue  # seen recently, not a priority
            # Closer and longer-unvisited customers first.
            score = distance - min(days if days is not None else 60, 60) * 0.05
            row = client_data(partner, lat, lng)
            row.update(reason='Never visited' if days is None else 'Not visited for %d days' % days,
                       distance_km=round(distance, 2), _score=score)
            nearby.append(row)
        nearby.sort(key=lambda r: r.pop('_score'))
        return ok({
            'enabled': True,
            'planned': planned_rows,
            'planned_km': round(total, 2),
            'nearby': nearby[:10],
            'radius_km': radius,
        })
