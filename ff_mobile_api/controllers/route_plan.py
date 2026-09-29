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
            # A route drawn in the app may still be waiting for the office.
            'approval_state': route.ff_approval_state,
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
            # The same shop can be called on twice in a day; this only says so.
            'already_planned': request.env['ff.beat.plan'].ff_already_planned(
                employee, route, fields.Date.to_date(date) if date else None),
            'customers': [dict(client_data(row['partner']),
                               sequence=row['sequence'],
                               selected=row['selected'],
                               status=row['status'] or None,
                               visited=row['visited']) for row in customers],
        })

    @api_route('/api/v1/route-types', methods=('GET',))
    def route_types(self, employee, **kw):
        """The kinds of route this person's department uses."""
        types = request.env['ff.route.type'].ff_for_employee(employee)
        return ok([{'id': t.id, 'name': t.name} for t in types])

    @api_route('/api/v1/beats', methods=('POST',))
    def create_beat(self, employee, **kw):
        """Draw a route from the app.

        The field is the side that finds out a patch of town has been missed,
        so it can draw the route there and then. Whether the office sees it
        first is the office's own setting.
        """
        beat = request.env['ff.beat'].ff_create_from_app(employee, body())
        return ok(beat.ff_app_payload(), status=201)

    @api_route('/api/v1/beats/<int:beat_id>/customers', methods=('POST',))
    def add_beat_customers(self, employee, beat_id, **kw):
        """Put customers on a route, at the end of it."""
        beat = request.env['ff.beat'].sudo().browse(beat_id).exists()
        if not beat:
            raise ApiError('Route not found.', 404, 'not_found')
        data = body()
        added = request.env['ff.beat'].ff_add_customers_from_app(
            employee, beat, data.get('partner_ids') or [])
        return ok(dict(beat.ff_app_payload(), added=len(added)), status=201)

    @api_route('/api/v1/beats/<int:beat_id>/decide', methods=('POST',))
    def decide_beat(self, employee, beat_id, **kw):
        """A manager approves or turns down a route their field drew."""
        beat = request.env['ff.beat'].sudo().browse(beat_id).exists()
        if not beat:
            raise ApiError('Route not found.', 404, 'not_found')
        approve = bool(body().get('approve'))
        return ok(beat.ff_decide_from_app(employee, approve).ff_app_payload())

    @api_route('/api/v1/route-plan/contacts', methods=('GET',))
    def plan_contacts(self, employee, date=None, q=None, member=None, **kw):
        """Everything plannable, as one list, for picking customers instead of a route.

        One list rather than a heap of beats: a lead has no beat at all, and
        somebody looking for a shop by name should not have to know which beat
        it is on first. Each row still says which beat it sits on.
        """
        employee, _label = _one(employee, member)
        day = fields.Date.to_date(date) if date else None
        Plan = request.env['ff.beat.plan']
        partners, chosen, visited = Plan.ff_app_plan_contacts(employee, day, (q or '').strip())
        also = Plan.ff_already_planned_partners(employee, partners, day)
        rows = [dict(
            client_data(partner),
            beat=ref(partner.ff_route_ids[:1]),
            selected=partner.id in chosen,
            visited=partner.id in visited,
            also_planned_by=also.get(partner.id) or [],
        ) for partner in partners]
        # Never visited first, then the longest unvisited: the ones worth a day out.
        rows.sort(key=lambda row: (-(row['days_since_visit'] if row['days_since_visit'] is not None else 10 ** 6),
                                   row['name'] or ''))
        return ok({'total': len(partners), 'contacts': rows})

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
        # Picked customer by customer: no route, one day, whatever beats they sit on.
        if data.get('partner_ids') and not data.get('beat_id'):
            return ok(plan_data(Plan.ff_plan_contacts_from_app(target, data)), status=201)
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
