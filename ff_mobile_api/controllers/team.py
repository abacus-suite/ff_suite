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
