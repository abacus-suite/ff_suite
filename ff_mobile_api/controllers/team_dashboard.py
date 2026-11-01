"""The team's day in one answer: who is in, what they have done and what needs a manager's eye."""
from datetime import timedelta

from odoo import http
from odoo.http import request

from odoo.addons.ff_base.tools import to_iso

from .common import api_route, ok, ref


def _span(employee, period):
    today = employee._ff_today()
    if period == 'yesterday':
        first = last = today - timedelta(days=1)
    elif period == 'week':
        first, last = today - timedelta(days=today.weekday()), today
    elif period == 'month':
        first, last = today.replace(day=1), today
    else:
        period, first, last = 'today', today, today
    return period, first, last


class FieldForceTeamDashboardApi(http.Controller):

    @api_route('/api/v1/team/dashboard', methods=('GET',), manager=True)
    def dashboard(self, employee, period='today', **kw):
        env = request.env
        team = employee._ff_subordinates()
        period, first, last = _span(employee, period)
        start, end = employee._ff_day_bounds(first)[0], employee._ff_day_bounds(last)[1]
        today = employee._ff_today()
        t_start, t_end = employee._ff_day_bounds(today)
        ids = team.ids

        def rows(model, domain, **kw_):
            return env[model].sudo().search(domain, **kw_) if model in env else env['res.partner'].browse()

        # ---- today's presence: always about today, whatever period is chosen
        attendances = rows('hr.attendance', [('employee_id', 'in', ids), ('check_in', '>=', t_start), ('check_in', '<', t_end)])
        present = {a.employee_id.id for a in attendances}

        def _get_late_minutes(a):
            late_min = getattr(a, 'ff_late_minutes', 0)
            shift = getattr(a, 'ff_shift_id', None) or getattr(a.employee_id, 'ff_shift_id', None)
            if not late_min and shift and a.check_in and a.employee_id:
                local_in = a.employee_id._ff_to_local(a.check_in)
                hours, minutes = divmod(shift._ff_start_minutes(), 60)
                start_dt = local_in.replace(hour=hours, minute=minutes, second=0, microsecond=0)
                late_min = max(0, int((local_in - start_dt).total_seconds() // 60))
            return late_min

        def _is_late(a):
            if getattr(a, 'ff_day_status', '') == 'late':
                return True
            late_min = _get_late_minutes(a)
            shift = getattr(a, 'ff_shift_id', None) or getattr(a.employee_id, 'ff_shift_id', None)
            if shift:
                return late_min > shift.grace_minutes
            return late_min > 0

        late = {a.employee_id.id: _get_late_minutes(a) for a in attendances if _is_late(a)}
        leaves = rows('hr.leave', [('employee_id', 'in', ids), ('state', '=', 'validate'),
                                   ('request_date_from', '<=', today), ('request_date_to', '>=', today)])
        on_leave = {leave.employee_id.id for leave in leaves}
        statuses = {s.employee_id.id: s for s in rows('ff.employee.status', [('employee_id', 'in', ids)])}
        ongoing = {v.employee_id.id: v for v in rows('ff.visit', [('employee_id', 'in', ids), ('state', '=', 'ongoing')])}

        # ---- the period's work, per person
        per = {m.id: {'visits': 0, 'productive': 0, 'planned': 0, 'planned_done': 0, 'orders': 0, 'order_amount': 0.0,
                      'collections': 0.0, 'km': 0.0} for m in team}
        for visit in rows('ff.visit', [('employee_id', 'in', ids), ('check_in_at', '>=', start), ('check_in_at', '<', end)]):
            row = per[visit.employee_id.id]
            row['visits'] += 1
            row['productive'] += 1 if getattr(visit, 'productive', False) else 0
        for line in rows('ff.route.plan.customer', [('day_id.employee_id', 'in', ids), ('day_id.date', '>=', first),
                                                    ('day_id.date', '<=', last), ('selected', '=', True)]):
            row = per[line.day_id.employee_id.id]
            row['planned'] += 1
            row['planned_done'] += 1 if line.visit_id else 0
        for order in rows('sale.order', [('ff_employee_id', 'in', ids), ('ff_source', '=', 'app'), ('state', '!=', 'cancel'),
                                         ('date_order', '>=', start), ('date_order', '<', end)]):
            if order.ff_demand_ids if 'ff_demand_ids' in order._fields else False:
                continue  # the demand it came from is already counted
            row = per[order.ff_employee_id.id]
            row['orders'] += 1
            row['order_amount'] += order.amount_total
        for demand in rows('ff.demand', [('employee_id', 'in', ids), ('state', '!=', 'cancelled'),
                                         ('date', '>=', start), ('date', '<', end)]):
            row = per[demand.employee_id.id]
            row['orders'] += 1
            row['order_amount'] += demand.amount_total
        for coll in rows('ff.collection', [('employee_id', 'in', ids), ('date', '>=', start), ('date', '<', end)]):
            per[coll.employee_id.id]['collections'] += coll.amount
        for track in rows('ff.daily.track', [('employee_id', 'in', ids), ('date', '>=', first), ('date', '<=', last)]):
            per[track.employee_id.id]['km'] += track.distance_km

        members = []
        for member in team.sorted('name'):
            status = statuses.get(member.id)
            visit = ongoing.get(member.id)
            if member.id in on_leave:
                state = 'leave'
            elif status and status.punched_in:
                state = 'in'
            elif member.id in present:
                state = 'out'
            else:
                state = 'absent'
            row = per[member.id]
            members.append({
                'employee': ref(member),
                'team': ref(member.ff_team_id),
                'state': state,
                'checked_in_at': to_iso(status.punched_in_at) if status and status.punched_in else None,
                'late_minutes': late.get(member.id) or 0,
                'at_client': ref(visit.partner_id) if visit else None,
                'battery': status.battery if status and status.punched_in else None,
                'low_battery': bool(status and status.punched_in and status.is_low_battery),
                'gps_off': bool(status and status.punched_in and status.gps_on is False),
                'inactive': bool(status and status.punched_in and status.is_inactive),
                'no_signal': bool(status and status.punched_in and status.is_signal_lost),
                'visits': row['visits'], 'productive': row['productive'],
                'planned': row['planned'], 'planned_done': row['planned_done'],
                'orders': row['orders'], 'order_amount': round(row['order_amount'], 2),
                'collections': round(row['collections'], 2), 'km': round(row['km'], 1),
            })

        def total(key):
            return sum(m[key] for m in members)

        counts = {k: sum(1 for m in members if m['state'] == k) for k in ('in', 'out', 'absent', 'leave')}
        # ---- a week's shape, for the trend: orders and visits per day
        days = []
        for back in range(6, -1, -1):
            day = today - timedelta(days=back)
            d_start, d_end = employee._ff_day_bounds(day)
            amount = 0.0
            for order in rows('sale.order', [('ff_employee_id', 'in', ids), ('ff_source', '=', 'app'), ('state', '!=', 'cancel'),
                                             ('date_order', '>=', d_start), ('date_order', '<', d_end)]):
                if not (order.ff_demand_ids if 'ff_demand_ids' in order._fields else False):
                    amount += order.amount_total
            amount += sum(d.amount_total for d in rows('ff.demand', [('employee_id', 'in', ids), ('state', '!=', 'cancelled'),
                                                                     ('date', '>=', d_start), ('date', '<', d_end)]))
            visits = len(rows('ff.visit', [('employee_id', 'in', ids), ('check_in_at', '>=', d_start), ('check_in_at', '<', d_end)]))
            days.append({'date': day.isoformat(), 'label': day.strftime('%a'), 'amount': round(amount, 2), 'visits': visits})

        # ---- what needs a manager's eye
        work_alerts = []
        tomorrow = today + timedelta(days=1)
        planned_tomorrow = {p.employee_id.id for p in rows('ff.beat.plan', [('employee_id', 'in', ids),
                                                                            ('date', '=', tomorrow)])}
        missing_plan = [p.name for p in team if p.id not in planned_tomorrow]
        if missing_plan:
            work_alerts.append({'key': 'beat_not_planned', 'title': "Tomorrow's beat not planned",
                                'names': missing_plan[:8], 'people': missing_plan[:8], 'count': len(missing_plan)})
        y_start, y_end = employee._ff_day_bounds(today - timedelta(days=1))
        missed = rows('hr.attendance', [('employee_id', 'in', ids), ('check_in', '>=', y_start),
                                        ('check_in', '<', y_end), ('check_out', '=', False)])
        if missed:
            names = sorted({a.employee_id.name for a in missed})
            work_alerts.append({'key': 'missed_checkout', 'title': 'Missed check-out yesterday',
                                'names': names[:8], 'people': names[:8], 'count': len(names)})
        unsent = rows('ff.expense.claim', [('employee_id', 'in', ids), ('state', '=', 'draft')])
        if unsent:
            names = sorted({c.employee_id.name for c in unsent})
            work_alerts.append({'key': 'expenses_not_sent', 'title': 'Expenses not sent (Mon 10 am)',
                                'names': names[:8], 'people': names[:8], 'count': len(names)})

        return ok({
            'period': period, 'from': first.isoformat(), 'to': last.isoformat(), 'currency': employee.company_id.currency_id.name,
            'people': {'total': len(members), 'in': counts['in'], 'out': counts['out'], 'absent': counts['absent'],
                       'leave': counts['leave'], 'present': counts['in'] + counts['out'], 'late': len(late)},
            'totals': {'visits': total('visits'), 'productive': total('productive'), 'planned': total('planned'),
                       'planned_done': total('planned_done'), 'orders': total('orders'),
                       'order_amount': round(total('order_amount'), 2), 'collections': round(total('collections'), 2),
                       'km': round(total('km'), 1)},
            'alerts': {'no_signal': sum(1 for m in members if m['no_signal']), 'low_battery': sum(1 for m in members if m['low_battery']),
                       'gps_off': sum(1 for m in members if m['gps_off']), 'inactive': sum(1 for m in members if m['inactive'])},
            'work_alerts': work_alerts,
            'members': members,
            'trend': days,
        })
