"""Planning route days from the app."""
from odoo import fields, http
from odoo.http import request

from .common import ApiError, api_route, body, ok, ref, scope_members
from .field_data import client_data, plan_data


class FieldForceRoutePlanApi(http.Controller):

    @api_route('/api/v1/route-plan/routes', methods=('GET',))
    def routes(self, employee, member=None, **kw):
        target, _label = _one(employee, member)
        routes = request.env['ff.beat.plan'].ff_app_routes(target)
        return ok([{
            'id': route.id,
            'name': route.display_name,
            'route_type': route.route_type_id.name or None,
            # So a new customer on this route can take its city without typing it.
            'district': ref(route.district_id),
            'city': route.district_id.name or None,
            'state': ref(route.state_id),
            'customer_count': len(route.line_ids),
            'planned_km': round(route.planned_km, 1),
        } for route in routes])

    @api_route('/api/v1/route-plan/customers', methods=('GET',))
    def customers(self, employee, beat_id=None, date=None, member=None, **kw):
        employee, _label = _one(employee, member)
        route = request.env['ff.beat'].sudo().browse(int(beat_id or 0)).exists()
        if not route:
            raise ApiError('Choose a route.', 404, 'not_found')
        day, customers = request.env['ff.beat.plan'].ff_app_route_customers(
            employee, route, fields.Date.to_date(date) if date else None)
        return ok({
            'route': ref(route),
            'day': plan_data(day) if day else None,
            'customers': [dict(client_data(row['partner']),
                               sequence=row['sequence'],
                               selected=row['selected'],
                               status=row['status'] or None,
                               visited=row['visited']) for row in customers],
        })

    @api_route('/api/v1/route-plan/days', methods=('GET',))
    def days(self, employee, start=None, end=None, member=None, **kw):
        """What is already planned (for me, my team or one member)."""
        people, _label = scope_members(employee, member)
        domain = [('employee_id', 'in', people.ids)]
        if start:
            domain.append(('date', '>=', fields.Date.to_date(start)))
        if end:
            domain.append(('date', '<=', fields.Date.to_date(end)))
        days = request.env['ff.beat.plan'].sudo().search(domain, order='date, employee_id', limit=300)
        return ok([dict(plan_data(day), employee=ref(day.employee_id)) for day in days])

    @api_route('/api/v1/route-plan/days', methods=('POST',))
    def plan_day(self, employee, **kw):
        """Plan one route, or several at once with ``routes: [{beat_id, partner_ids}]``,
        for me or (``member``) someone in my team."""
        data = body()
        target, _label = _one(employee, data.get('member'))
        # sudo: the result set is read afterwards, and an empty non-sudo set would take the union's access rights.
        Plan = request.env['ff.beat.plan'].sudo()
        if data.get('routes'):
            days = Plan.browse()
            for row in data['routes']:
                days |= Plan.ff_plan_from_app(target, dict(row, date=data.get('date')))
            return ok({'days': [plan_data(day) for day in days], 'employee': ref(target)}, status=201)
        day = Plan.ff_plan_from_app(target, data)
        return ok(plan_data(day), status=201)


def _one(employee, member):
    """Myself, or one employee in my team - never the whole team."""
    if member in (None, '', 'me', 'team'):
        return employee, employee.name
    return scope_members(employee, member)
