"""Manager endpoints: live team, timeline replay and approvals.

"Team" = the employees inside the caller's Data Access scope (excluding self).
"""
from odoo import fields, http
from odoo.http import request

from odoo.addons.ff_base.tools import to_iso

from .common import ApiError, api_route, attendance_data, ok, ref, regularisation_data
from .field_data import client_data, plan_data, visit_data

MAX_TIMELINE_POINTS = 1500


def _team(employee):
    return employee._ff_subordinates()


def _member(employee, employee_id):
    target = request.env['hr.employee'].sudo().browse(employee_id).exists()
    if not target or (target != employee and target not in _team(employee)):
        raise ApiError('Employee not found in your team.', 404, 'not_found')
    return target


def _path(employee, target):
    """Breadcrumb from me down to ``target``."""
    if target == employee:
        return [employee]
    chain, person = [], target
    while person and person != employee and len(chain) < 20:
        chain.insert(0, person)
        person = person.parent_id
    return [employee] + chain


class FieldForceTeamApi(http.Controller):

    @api_route('/api/v1/team/members', methods=('GET',))
    def members(self, employee, **kw):
        """People this employee may pick on any screen (their Data Access), for the me / team / person picker."""
        team = _team(employee)
        return ok({
            'can_team': bool(team),
            'members': [dict(ref(member), code=member.ff_employee_code or None, team=ref(member.ff_team_id))
                        for member in team.sorted('name')],
        })

    @api_route('/api/v1/team/tree', methods=('GET',))
    def tree(self, employee, root=None, start=None, end=None, expand=None, **kw):
        """The team as a tree: the people directly under ``root`` (me by default),
        each with a few figures for the period and how many are under them.
        ``expand=1`` returns every level at once."""
        env = request.env
        scope = employee | _team(employee)
        top = _member(employee, int(root)) if root and str(root) not in ('me', '0') else employee
        today = employee._ff_today()
        low = fields.Date.to_date(start) if start else today.replace(day=1)
        high = fields.Date.to_date(end) if end else today
        children_of = {}
        for person in scope:
            if person.parent_id and person.parent_id != person:
                children_of.setdefault(person.parent_id.id, []).append(person)

        def under(person, seen=None):
            seen = seen if seen is not None else set()
            found = env['hr.employee'].sudo()
            for child in children_of.get(person.id, []):
                if child.id in seen:
                    continue
                seen.add(child.id)
                found |= child | under(child, seen)
            return found

        everyone = top | under(top)
        start_dt, end_dt = employee._ff_day_bounds(low)[0], employee._ff_day_bounds(high)[1]
        today_start, today_end = employee._ff_day_bounds(today)
        statuses = {s.employee_id.id: s for s in env['ff.employee.status'].sudo().search(
            [('employee_id', 'in', everyone.ids)])}

        def counts(model, field, date_field, low_value, high_value, extra=None, amount=None):
            if model not in env:
                return {}
            domain = [(field, 'in', everyone.ids), (date_field, '>=', low_value), (date_field, '<', high_value)]
            aggregates = ['__count'] + ([amount + ':sum'] if amount else [])
            return {row[0].id: row[1:] for row in env[model].sudo()._read_group(domain + (extra or []), [field], aggregates)}

        visits_today = counts('ff.visit', 'employee_id', 'check_in_at', today_start, today_end)
        visits = counts('ff.visit', 'employee_id', 'check_in_at', start_dt, end_dt)
        flow = env['ir.config_parameter'].sudo().get_param('ff_base.order_flow') or 'direct'
        if flow == 'demand' and 'ff.demand' in env:
            sales = counts('ff.demand', 'employee_id', 'date', start_dt, end_dt,
                           [('state', '!=', 'cancelled')], 'amount_total')
        else:
            sales = counts('sale.order', 'ff_employee_id', 'date_order', start_dt, end_dt,
                           [('state', '!=', 'cancel')], 'amount_total')
        collections = counts('ff.collection', 'employee_id', 'date', start_dt, end_dt,
                             [('state', '!=', 'cancelled')], 'amount')

        def value(table, person_id, index):
            row = table.get(person_id)
            return (row[index] or 0) if row else 0

        def node(person, deep):
            status = statuses.get(person.id)
            below = under(person)
            direct = sorted(children_of.get(person.id, []), key=lambda c: c.name or '')
            group = person | below
            row = {
                'id': person.id, 'name': person.name, 'code': person.ff_employee_code or None,
                'job': person.job_title or person.ff_designation_id.name or None,
                'team': ref(person.ff_team_id),
                'punched_in': bool(status and status.punched_in),
                'last_ping_at': to_iso(status.last_ping_at) if status else None,
                'direct_count': len(direct), 'team_count': len(below),
                'visits_today': value(visits_today, person.id, 0),
                'visits': value(visits, person.id, 0),
                'sales': round(value(sales, person.id, 1), 2),
                'collections': round(value(collections, person.id, 1), 2),
                # Figures for this person together with everybody under them.
                'team_visits': sum(value(visits, p.id, 0) for p in group),
                'team_sales': round(sum(value(sales, p.id, 1) for p in group), 2),
                'team_collections': round(sum(value(collections, p.id, 1) for p in group), 2),
                'punched_in_count': sum(1 for p in group if statuses.get(p.id) and statuses[p.id].punched_in),
            }
            if deep:
                row['children'] = [node(child, True) for child in direct]
            return row

        data = node(top, bool(expand))
        if not expand:
            data['children'] = [node(child, False) for child in sorted(children_of.get(top.id, []),
                                                                         key=lambda c: c.name or '')]
        return ok({'root': data, 'start': low.isoformat(), 'end': high.isoformat(),
                   'currency': employee.company_id.currency_id.name,
                   'path': [ref(p) for p in _path(employee, top)]})

    @api_route('/api/v1/team/live', methods=('GET',), manager=True)
    def live(self, employee, **kw):
        team = _team(employee)
        statuses = {s.employee_id.id: s for s in request.env['ff.employee.status'].sudo().search(
            [('employee_id', 'in', team.ids)])}
        ongoing = {v.employee_id.id: v for v in request.env['ff.visit'].sudo().search(
            [('employee_id', 'in', team.ids), ('state', '=', 'ongoing')])}
        members, summary = [], {'total': len(team), 'punched_in': 0, 'inactive': 0,
                                'no_signal': 0, 'low_battery': 0, 'gps_off': 0, 'at_client': 0}
        for member in team.sorted('name'):
            status = statuses.get(member.id)
            punched_in = bool(status and status.punched_in)
            visit = ongoing.get(member.id)
            row = {
                'employee': ref(member),
                'code': member.ff_employee_code or None,
                'team': ref(member.ff_team_id),
                'punched_in': punched_in,
                'punched_in_at': to_iso(status.punched_in_at) if status else None,
                'last_ping_at': to_iso(status.last_ping_at) if status else None,
                'lat': status.latitude if status and status.last_ping_at else None,
                'lng': status.longitude if status and status.last_ping_at else None,
                'battery': status.battery if status and status.last_ping_at else None,
                'is_low_battery': bool(status and status.is_low_battery),
                'gps_on': bool(status.gps_on) if status else None,
                'is_inactive': bool(status and status.is_inactive),
                'is_signal_lost': bool(status and status.is_signal_lost),
                'at_client': ref(visit.partner_id) if visit else None,
            }
            members.append(row)
            if punched_in:
                summary['punched_in'] += 1
                summary['inactive'] += row['is_inactive']
                summary['no_signal'] += row['is_signal_lost']
                summary['low_battery'] += row['is_low_battery']
                summary['gps_off'] += row['gps_on'] is False
            summary['at_client'] += bool(visit)
        return ok({'summary': summary, 'members': members, 'server_time': to_iso(fields.Datetime.now())})

    @api_route('/api/v1/team/<int:employee_id>/timeline', methods=('GET',), manager=True)
    def timeline(self, employee, employee_id, date=None, **kw):
        target = _member(employee, employee_id)
        try:
            day = fields.Date.to_date(date) if date else target._ff_today()
        except ValueError:
            raise ApiError('date must be YYYY-MM-DD.')
        start, end = target._ff_day_bounds(day)
        pings = request.env['ff.location.ping'].sudo().search([
            ('employee_id', '=', target.id), ('ts', '>=', start), ('ts', '<', end),
        ], order='ts asc')
        step = len(pings) // MAX_TIMELINE_POINTS + 1
        sampled = pings[::step]
        if pings and sampled[-1] != pings[-1]:
            sampled |= pings[-1]
        attendances = request.env['hr.attendance'].sudo().search([
            ('employee_id', '=', target.id), ('check_in', '>=', start), ('check_in', '<', end),
        ], order='check_in asc')
        visits = request.env['ff.visit'].sudo().search([
            ('employee_id', '=', target.id), ('check_in_at', '>=', start), ('check_in_at', '<', end),
        ], order='check_in_at asc')
        plan = request.env['ff.beat.plan'].sudo().search(
            [('employee_id', '=', target.id), ('date', '=', day)], limit=1)
        track = request.env['ff.daily.track']._ff_compute(target, day)
        return ok({
            'employee': ref(target),
            'date': day.isoformat(),
            'distance_km': track.distance_km if track else 0.0,
            'attendance': [attendance_data(a) for a in attendances],
            'visits': [visit_data(v) for v in visits],
            'plan': plan_data(plan),
            'points': [{
                'ts': to_iso(p.ts), 'lat': p.latitude, 'lng': p.longitude,
                'accuracy': p.accuracy, 'battery': p.battery, 'source': p.source, 'mock': p.is_mock,
            } for p in sampled],
        })

    @api_route('/api/v1/approvals', methods=('GET',), manager=True)
    def approvals(self, employee, **kw):
        team = _team(employee)
        regularisations = request.env['ff.regularisation'].sudo().search([
            ('employee_id', 'in', team.ids), ('state', '=', 'submitted'),
        ])
        clients = request.env['res.partner'].sudo().search([
            ('ff_is_client', '=', True), ('ff_approval_state', '=', 'pending'),
            ('ff_created_by_employee_id', 'in', team.ids),
        ])
        return ok({
            'regularisation': [regularisation_data(r) for r in regularisations],
            'clients': [dict(client_data(c), added_by=ref(c.ff_created_by_employee_id),
                             added_at=to_iso(c.create_date)) for c in clients],
        })

    @api_route('/api/v1/approvals/regularisation/<int:record_id>/<string:decision>',
               methods=('POST',), manager=True)
    def decide_regularisation(self, employee, record_id, decision, **kw):
        if decision not in ('approve', 'reject'):
            raise ApiError('decision must be "approve" or "reject".')
        record = request.env['ff.regularisation'].sudo().browse(record_id).exists()
        if not record or record.employee_id not in _team(employee):
            raise ApiError('Request not found.', 404, 'not_found')
        record._ff_decide_as(employee, decision == 'approve')
        return ok(regularisation_data(record))

    @api_route('/api/v1/approvals/client/<int:partner_id>/<string:decision>',
               methods=('POST',), manager=True)
    def decide_client(self, employee, partner_id, decision, **kw):
        if decision not in ('approve', 'reject'):
            raise ApiError('decision must be "approve" or "reject".')
        partner = request.env['res.partner'].sudo().browse(partner_id).exists()
        if not partner or partner.ff_approval_state != 'pending':
            raise ApiError('Client request not found.', 404, 'not_found')
        partner.ff_app_decide(employee, decision == 'approve')
        return ok(client_data(partner))
