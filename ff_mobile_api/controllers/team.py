"""Manager endpoints: live team, timeline replay and approvals."""
from odoo import fields, http
from odoo.http import request

from odoo.addons.ff_base.tools import to_iso

from .common import ApiError, api_route, attendance_data, ok, ref, regularisation_data

MAX_TIMELINE_POINTS = 1500


def _team(employee):
    if request.env.user.has_group('ff_base.group_ff_admin'):
        return request.env['hr.employee'].sudo().search([('id', '!=', employee.id), ('user_id', '!=', False)])
    return employee._ff_subordinates()


def _member(employee, employee_id):
    target = request.env['hr.employee'].sudo().browse(employee_id).exists()
    if not target or (target != employee and target not in _team(employee)):
        raise ApiError('Employee not found in your team.', 404, 'not_found')
    return target


class FieldForceTeamApi(http.Controller):

    @api_route('/api/v1/team/live', methods=('GET',), manager=True)
    def live(self, employee, **kw):
        team = _team(employee)
        statuses = {s.employee_id.id: s for s in request.env['ff.employee.status'].sudo().search(
            [('employee_id', 'in', team.ids)])}
        members, summary = [], {'total': len(team), 'punched_in': 0, 'inactive': 0,
                                'no_signal': 0, 'low_battery': 0, 'gps_off': 0}
        for member in team.sorted('name'):
            status = statuses.get(member.id)
            punched_in = bool(status and status.punched_in)
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
            }
            members.append(row)
            if punched_in:
                summary['punched_in'] += 1
                summary['inactive'] += row['is_inactive']
                summary['no_signal'] += row['is_signal_lost']
                summary['low_battery'] += row['is_low_battery']
                summary['gps_off'] += row['gps_on'] is False
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
        track = request.env['ff.daily.track']._ff_compute(target, day)
        return ok({
            'employee': ref(target),
            'date': day.isoformat(),
            'distance_km': track.distance_km if track else 0.0,
            'attendance': [attendance_data(a) for a in attendances],
            'points': [{
                'ts': to_iso(p.ts), 'lat': p.latitude, 'lng': p.longitude,
                'accuracy': p.accuracy, 'battery': p.battery, 'source': p.source, 'mock': p.is_mock,
            } for p in sampled],
        })

    @api_route('/api/v1/approvals', methods=('GET',), manager=True)
    def approvals(self, employee, **kw):
        regularisations = request.env['ff.regularisation'].sudo().search([
            ('employee_id', 'in', _team(employee).ids), ('state', '=', 'submitted'),
        ])
        return ok({
            'regularisation': [regularisation_data(r) for r in regularisations],
        })

    @api_route('/api/v1/approvals/regularisation/<int:record_id>/<string:decision>',
               methods=('POST',), manager=True)
    def decide_regularisation(self, employee, record_id, decision, **kw):
        record = request.env['ff.regularisation'].sudo().browse(record_id).exists()
        if not record or record.employee_id not in _team(employee):
            raise ApiError('Request not found.', 404, 'not_found')
        if decision == 'approve':
            record.action_approve()
        elif decision == 'reject':
            record.action_reject()
        else:
            raise ApiError('decision must be "approve" or "reject".')
        return ok(regularisation_data(record))
