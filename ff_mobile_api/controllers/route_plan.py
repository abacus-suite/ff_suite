"""Planning route days from the app."""
from datetime import timedelta

from odoo import fields, http
from odoo.http import request

from .clients import to_int
from .common import ApiError, api_route, body, note_rejection, ok, ref, scope_members
from .field_data import client_data, plan_data


class FieldForceRoutePlanApi(http.Controller):

    @api_route('/api/v1/route-plan/routes', methods=('GET',))
    def routes(self, employee, member=None, **kw):
        target, _label = _one(employee, member)
        routes = request.env['ff.beat.plan'].ff_app_routes(target)
        return ok([{
            'id': route.id,
            'name': route.name,
            'route_type': route.route_type_id.name or None,
            # So a new customer on this route can take its city without typing it.
            'district': ref(route.district_id),
            'city': route.district_id.name or None,
            'state': ref(route.state_id),
            'customer_count': len(route.line_ids),
            'planned_km': round(route.planned_km, 1),
            # A route drawn in the app may still be waiting for the office.
            'approval_state': route.ff_approval_state,
            'added_by': ref(route.ff_created_by_employee_id) or {'id': 0, 'name': 'Office'},
            'code': route.code or None,
            'territory': ref(route.territory_id) if 'territory_id' in route._fields else None,
            # Repeat on or off: a recurrent beat with weekdays repeats on them; without, it repeats on none.
            'schedule': route.ff_schedule or None,
            'weekdays': [int(d) for d in (route.ff_weekdays or '').split(',') if d],
            'plan_dates': [d for d in (route.ff_plan_dates or '').split(',') if d],
            'delete_requested': bool(route.ff_delete_requested),
        } for route in routes])

    @api_route('/api/v1/route-plan/customers', methods=('GET',))
    def customers(self, employee, beat_id=None, date=None, member=None, **kw):
        employee, _label = _one(employee, member)
        route = request.env['ff.beat'].sudo().browse(int(beat_id or 0)).exists()
        if not route:
            raise ApiError('Choose a route.', 404, 'not_found')
        if not request.env['ff.beat'].ff_can_use_beat(employee, route):
            raise ApiError('That route is not one of yours.', 403, 'forbidden')
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

    @api_route('/api/v1/territories', methods=('GET',))
    def territories(self, employee, member=None, **kw):
        """The territories this person works in, with the outlets that sit on a beat of each."""
        env = request.env
        if member not in (None, '', 'me'):
            employee, _label = _one(employee, member)  # a manager drawing a beat for somebody in the team
        if 'ff.territory' not in env:
            return ok([])
        primary = employee.ff_territory_ids if 'ff_territory_ids' in employee._fields else env['ff.territory'].browse()
        secondary = env['ff.territory'].browse()
        if 'ff_secondary_territory' in employee._fields and employee.ff_secondary_territory:
            secondary |= employee.ff_secondary_territory
        if 'ff_secondary_territory_ids' in employee._fields and employee.ff_secondary_territory_ids:
            secondary |= employee.ff_secondary_territory_ids
        mine = primary | secondary
        if 'ff.contact.access.request' in env:
            today = fields.Date.context_today(employee)
            grants = env['ff.contact.access.request'].sudo().search([
                ('employee_id', '=', employee.id), ('scope_type', '=', 'territory'), ('state', '=', 'approved'),
                ('date_from', '<=', today), ('date_to', '>=', today)])
            if grants:
                mine |= grants.mapped('territory_id').filtered(lambda t: t.exists())
        if not mine:
            mine = env['ff.territory'].sudo().search([], limit=300)

        secondary_ids = set((secondary - primary).ids)
        beats = env['ff.beat'].sudo().search([('territory_id', 'in', mine.ids)])
        lines = env['ff.beat.line'].sudo().search([('beat_id', 'in', beats.ids)])
        territory_of = {beat.id: beat.territory_id.id for beat in beats}
        by_territory = {}
        for line in lines:
            partner = line.partner_id
            if not partner.active:
                continue
            by_territory.setdefault(territory_of.get(line.beat_id.id), {})[partner.id] = partner
        # A contact can also carry its territory directly, with no beat yet (primary or secondary).
        Partner = env['res.partner'].sudo()
        direct_domain = ['|', ('ff_territory_id', 'in', mine.ids), ('ff_secondary_territory_ids', 'in', mine.ids)] \
            if 'ff_secondary_territory_ids' in Partner._fields else [('ff_territory_id', 'in', mine.ids)]
        direct = Partner.search(direct_domain + [('active', '=', True)])
        for partner in direct:
            partner_tids = set()
            if partner.ff_territory_id:
                partner_tids.add(partner.ff_territory_id.id)
            if 'ff_secondary_territory_ids' in partner._fields and partner.ff_secondary_territory_ids:
                partner_tids.update(partner.ff_secondary_territory_ids.ids)
            for tid in partner_tids:
                if tid in mine.ids:
                    by_territory.setdefault(tid, {})[partner.id] = partner
        # Also include outlets in the territory's district that aren't assigned to any other territory yet
        for territory in mine:
            if territory.district_id and not by_territory.get(territory.id):
                unassigned = Partner.search([
                    ('active', '=', True),
                    ('ff_district_id', '=', territory.district_id.id),
                    ('ff_territory_id', '=', False),
                    ('ff_is_client', '=', True),
                ], limit=300)
                for p in unassigned:
                    by_territory.setdefault(territory.id, {})[p.id] = p
        out = []
        for territory in mine.sorted(lambda r: (r.name or '').lower()):
            partners = sorted(by_territory.get(territory.id, {}).values(), key=lambda p: (p.name or '').lower())
            is_sec = territory.id in secondary_ids
            has_area = 'ff_area_id' in request.env['res.partner']._fields
            counts = {}
            for p in partners[:1000]:
                if has_area and p.ff_area_id:
                    counts[p.ff_area_id.id] = counts.get(p.ff_area_id.id, 0) + 1
            areas = []
            if 'ff.area' in request.env:
                areas = [{'id': a.id, 'name': a.name, 'count': counts.get(a.id, 0)}
                         for a in request.env['ff.area'].sudo().search([('territory_id', '=', territory.id)])]
                areas.sort(key=lambda a: a['name'].lower())
            out.append({
                'id': territory.id,
                'name': territory.name,
                'district_id': territory.district_id.id or None,
                'is_secondary': is_sec,
                'kind': 'secondary' if is_sec else 'primary',
                # The Area master of this territory, with how many of its outlets sit in each (0 too).
                'areas': areas,
                'no_area_count': sum(1 for p in partners[:1000] if not (has_area and p.ff_area_id)),
                'outlets': [{'id': p.id, 'name': p.name, 'city': p.city or None,
                            'area': ref(p.ff_area_id) if has_area and p.ff_area_id else None,
                            'kind': getattr(p, 'ff_category_type', '') or 'outlet'} for p in partners[:1000]],
            })
        return ok(out)

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

    @api_route('/api/v1/beats/<int:beat_id>/update', methods=('POST',))
    def update_beat(self, employee, beat_id, **kw):
        """Change a beat I drew: which customers are on it, and the weekdays it repeats on."""
        beat = request.env['ff.beat'].sudo().browse(beat_id).exists()
        if not beat:
            raise ApiError('Route not found.', 404, 'not_found')
        beat = request.env['ff.beat'].ff_update_from_app(employee, beat, body())
        return ok(beat.ff_app_payload())

    @api_route('/api/v1/beats/<int:beat_id>/delete', methods=('POST',))
    def delete_beat(self, employee, beat_id, **kw):
        """Ask to delete a beat I drew: the manager decides, then it is archived."""
        beat = request.env['ff.beat'].sudo().browse(beat_id).exists()
        if not beat:
            raise ApiError('Route not found.', 404, 'not_found')
        beat, outcome = request.env['ff.beat'].ff_request_delete_from_app(employee, beat)
        return ok(dict(beat.ff_app_payload(), outcome=outcome))

    @api_route('/api/v1/beats/<int:beat_id>/unplan', methods=('POST',))
    def unplan_beat(self, employee, beat_id, **kw):
        """Take days off a beat's plan - some of them or all that are ahead. No approval is needed."""
        beat = request.env['ff.beat'].sudo().browse(beat_id).exists()
        if not beat:
            raise ApiError('Route not found.', 404, 'not_found')
        data = body()
        removed = request.env['ff.beat'].ff_unplan_from_app(
            employee, beat, dates=data.get('dates'), everything=bool(data.get('all')))
        return ok({'removed': removed})

    @api_route('/api/v1/beats/<int:beat_id>/plans', methods=('GET',))
    def beat_plans(self, employee, beat_id, member=None, **kw):
        """The days a beat was planned on for this person - upcoming, done and missed - and the days asked for
        that are still waiting for approval."""
        target, _label = _one(employee, member)
        beat = request.env['ff.beat'].sudo().browse(beat_id).exists()
        if not beat:
            raise ApiError('Beat not found.', 404, 'not_found')
        if beat.ff_created_by_employee_id != target and not request.env['ff.beat'].ff_can_use_beat(target, beat):
            raise ApiError('That beat is not one of yours.', 403, 'forbidden')
        days = request.env['ff.beat.plan'].sudo().search(
            [('employee_id', '=', target.id), ('beat_id', '=', beat.id)], order='date desc', limit=300)
        planned_on = set(days.mapped('date'))
        today = target._ff_today()
        requested = []
        if beat.ff_approval_state == 'pending':
            for text in (beat.ff_plan_dates or '').split(','):
                day = fields.Date.to_date(text) if text else None
                if day and day >= today and day not in planned_on:
                    requested.append(day.isoformat())
        return ok({
            'beat': ref(beat),
            'approval_state': beat.ff_approval_state,
            'days': [{
                'id': day.id,
                'date': day.date.isoformat(),
                'status': day.status,
                'planned_count': day.planned_count,
                'completed_count': day.completed_count,
                'missed_count': day.missed_count,
                'cancelled_count': day.cancelled_count,
            } for day in days],
            'requested': requested,
        })

    @api_route('/api/v1/beats/to-approve', methods=('GET',), manager=True)
    def beats_to_approve(self, employee, **kw):
        """Beats the team drew in the app that wait for a manager."""
        beats = request.env['ff.beat'].sudo().search([
            '|', ('ff_approval_state', '=', 'pending'), ('ff_delete_requested', '=', True),
            ('ff_created_by_employee_id', 'in', employee._ff_subordinates().ids)])
        return ok([dict(beat.ff_app_payload(), added_by=ref(beat.ff_created_by_employee_id)) for beat in beats])

    @api_route('/api/v1/beats/<int:beat_id>/decide', methods=('POST',))
    def decide_beat(self, employee, beat_id, **kw):
        """A manager approves or turns down a route their field drew."""
        beat = request.env['ff.beat'].sudo().browse(beat_id).exists()
        if not beat:
            raise ApiError('Route not found.', 404, 'not_found')
        approve = bool(body().get('approve'))
        decided = beat.ff_decide_from_app(employee, approve)
        note_rejection(beat, approve, employee)
        return ok(decided.ff_app_payload())

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
        if target != employee:
            # A manager planning a beat for somebody in the team also assigns it to them, so it is in their
            # My Beats (locked, "assigned by manager").
            Plan = Plan.with_context(ff_manager_plan=True)
            beat_ids = [to_int(data.get('beat_id'))] + [to_int(r.get('beat_id')) for r in (data.get('routes') or [])]
            beats = request.env['ff.beat'].sudo().browse([b for b in beat_ids if b]).exists()
            if beats:
                target.sudo().write({'ff_route_ids': [(4, b.id) for b in beats]})

        def make(date):
            """The plan for one date, in whichever of the three shapes it was sent."""
            if data.get('partner_ids') and not data.get('beat_id'):
                return Plan.ff_plan_contacts_from_app(target, dict(data, date=date))
            if data.get('routes'):
                days = Plan.browse()
                for row in data['routes']:
                    days |= Plan.ff_plan_from_app(target, dict(row, date=date))
                return days
            return Plan.ff_plan_from_app(target, dict(data, date=date))

        first = fields.Date.to_date(data.get('date')) or target._ff_today()
        made = make(first)

        # Repeated every week, like an alarm: the same plan on the same weekday
        # for the next so many weeks. A week that cannot take it - a holiday, the
        # weekly ceiling - is left out and said so, and never stops the others.
        repeat = max(min(to_int(data.get('repeat_weeks')) or 0, 12), 0)
        repeated, skipped = 0, []
        for week in range(1, repeat + 1):
            date = first + timedelta(days=7 * week)
            holiday = request.env['ff.holiday']._ff_for(target, date)
            if holiday:
                skipped.append({'date': date.isoformat(), 'reason': holiday.name})
                continue
            try:
                with request.env.cr.savepoint():
                    make(date)
                repeated += 1
            except Exception as error:
                skipped.append({'date': date.isoformat(), 'reason': str(error)[:140]})

        extra = {'repeated': repeated, 'skipped': skipped}
        if data.get('routes'):
            return ok(dict({'days': [plan_data(day) for day in made], 'employee': ref(target)}, **extra),
                      status=201)
        return ok(dict(plan_data(made), **extra), status=201)

    @api_route('/api/v1/route-plan/add-visit', methods=('POST',))
    def add_visit(self, employee, **kw):
        """Add a visit: the customers chosen join today's plan as planned stops.

        They then count in the day's summary and the Next Visit suggestion like any planned outlet, and start
        exactly as a planned visit does. They join today's plan whatever beat it is on; a customer already
        planned today is left where it is.
        """
        ids = {to_int(i) for i in (body().get('partner_ids') or []) if to_int(i)}
        if not ids:
            raise ApiError('Choose at least one customer.')
        Partner = request.env['res.partner'].sudo()
        allowed = Partner.search(Partner._ff_visible_domain(employee) + [('id', 'in', list(ids))])
        if len(allowed) != len(ids):
            raise ApiError('Some of those customers are not yours to visit.', 403, 'forbidden')
        today = employee._ff_today()
        Plan = request.env['ff.beat.plan'].sudo()
        days = Plan.search([('employee_id', '=', employee.id), ('date', '=', today)])
        day = days.filtered(lambda d: not d.beat_id)[:1] or days[:1]
        if not day:
            day = Plan.create({'employee_id': employee.id, 'date': today})
            day._ff_sync_plan_month()
        lines = days.customer_line_ids | day.customer_line_ids
        sequence = max(lines.mapped('sequence') or [0])
        Line = request.env['ff.route.plan.customer'].sudo()
        for partner in allowed:
            existing = lines.filtered(lambda l, p=partner: l.partner_id == p)
            if existing:
                existing.filtered(lambda l: not l.visit_id and not l.selected).write({'selected': True})
                continue
            sequence += 10
            Line.create({'day_id': day.id, 'partner_id': partner.id, 'sequence': sequence, 'selected': True})
        return ok({'added': len(allowed)})

    @api_route('/api/v1/route-plan/customers/cancel', methods=('POST',))
    def cancel_visit(self, employee, **kw):
        """Cancel a planned visit of today (with the reason), or plan it again with ``undo``.

        Only today's plan can be changed, and only for a customer not visited yet. A cancelled visit is counted
        under Cancelled in the day's summary.
        """
        data = body()
        partner_id = to_int(data.get('partner_id'))
        if not partner_id:
            raise ApiError('partner_id is required.')
        today = employee._ff_today()
        day = fields.Date.to_date(data.get('date')) if data.get('date') else today
        if day != today:
            raise ApiError('Only today\'s plan can be changed.', 400, 'invalid')
        lines = request.env['ff.route.plan.customer'].sudo().search([
            ('day_id.employee_id', '=', employee.id), ('day_id.date', '=', today),
            ('partner_id', '=', partner_id), ('selected', '=', True)])
        if not lines:
            raise ApiError('That customer is not in today\'s plan.', 404, 'not_found')
        if lines.filtered('visit_id'):
            raise ApiError('That customer was already visited today, so the visit cannot be cancelled.',
                           400, 'invalid')
        if data.get('undo'):
            lines.write({'cancelled': False, 'cancel_reason': False})
            return ok({'cancelled': False})
        reason = (data.get('reason') or '').strip()
        if not reason:
            raise ApiError('Give the reason for cancelling the visit.')
        lines.write({'cancelled': True, 'cancel_reason': reason})
        return ok({'cancelled': True})

    @api_route('/api/v1/route-plan/days/remove', methods=('POST',))
    def remove_day(self, employee, **kw):
        """Take one beat off a day. The beat stays in the beat list; only that day's plan goes.

        A person removes only a beat they drew themselves: one the manager assigned stays. A manager may
        remove a beat from a team member's day. A day with a visit already made, or a day gone by, stays.
        """
        data = body()
        target, _label = _one(employee, data.get('member'))
        Plan = request.env['ff.beat.plan'].sudo()
        plan = Plan.browse(to_int(data.get('plan_id'))).exists() if data.get('plan_id') else Plan.browse()
        if plan and plan.employee_id != target:
            raise ApiError('That plan is not yours.', 403, 'forbidden')
        if not plan:
            domain = [('employee_id', '=', target.id), ('date', '=', fields.Date.to_date(data.get('date')))]
            if data.get('beat_id'):
                domain.append(('beat_id', '=', to_int(data.get('beat_id'))))
            plan = Plan.search(domain, limit=1)
        if not plan:
            raise ApiError('That beat is not planned on this day.', 404, 'not_found')
        if target == employee:
            drawn_by = plan.beat_id.ff_created_by_employee_id
            if plan.beat_id and drawn_by != employee:
                raise ApiError('This beat was assigned to you by your manager, so it cannot be removed.',
                               403, 'forbidden')
        if plan.date < target._ff_today():
            raise ApiError('A day that has gone by cannot be changed.', 400, 'invalid')
        if plan.visit_ids:
            raise ApiError('A visit was already made on this beat that day, so it cannot be removed.',
                           400, 'invalid')
        plan.unlink()
        return ok({'removed': True})


def _one(employee, member):
    """Myself, or one employee in my team - never the whole team."""
    if member in (None, '', 'me', 'team'):
        return employee, employee.name
    return scope_members(employee, member)
