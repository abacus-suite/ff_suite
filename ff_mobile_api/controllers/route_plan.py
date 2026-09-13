"""Planning route days from the app."""
from odoo import fields, http
from odoo.http import request

from .common import ApiError, api_route, body, ok, ref
from .field_data import client_data, plan_data


class FieldForceRoutePlanApi(http.Controller):

    @api_route('/api/v1/route-plan/routes', methods=('GET',))
    def routes(self, employee, **kw):
        routes = request.env['ff.beat.plan'].ff_app_routes(employee)
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
    def customers(self, employee, beat_id=None, date=None, **kw):
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
    def days(self, employee, start=None, end=None, **kw):
        """What is already planned, to colour the calendar."""
        domain = [('employee_id', '=', employee.id)]
        if start:
            domain.append(('date', '>=', fields.Date.to_date(start)))
        if end:
            domain.append(('date', '<=', fields.Date.to_date(end)))
        days = request.env['ff.beat.plan'].sudo().search(domain, limit=200)
        return ok([plan_data(day) for day in days])

    @api_route('/api/v1/route-plan/days', methods=('POST',))
    def plan_day(self, employee, **kw):
        day = request.env['ff.beat.plan'].ff_plan_from_app(employee, body())
        return ok(plan_data(day), status=201)
