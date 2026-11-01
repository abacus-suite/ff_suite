"""Manager mode Home: one answer with the team's attendance, beat plan, overdue, tasks and alerts."""
from datetime import timedelta

from odoo import fields, http
from odoo.http import request

from odoo.addons.ff_base.tools import to_iso

from .clients import client_domain
from .common import api_route, ok, ref
from .team_dashboard import _span


class FieldForceTeamHomeApi(http.Controller):

    @api_route('/api/v1/team/home', methods=('GET',), manager=True)
    def home(self, employee, period='today', date=None, **kw):
        env = request.env
        team = employee._ff_subordinates()
        ids = team.ids
        period, first, last = _span(employee, period)
        if date:
            # A day picked on the calendar.
            first = last = fields.Date.to_date(date)
            period = 'date'
        start = employee._ff_day_bounds(first)[0]
        end = employee._ff_day_bounds(last)[1]
        today = employee._ff_today()

        def rows(model, domain, **options):
            return env[model].sudo().search(domain, **options) if model in env else env['res.partner'].browse()

        # ---- attendance for the chosen period
        attendances = rows('hr.attendance', [('employee_id', 'in', ids), ('check_in', '>=', start), ('check_in', '<', end)])
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

        late = {a.employee_id.id for a in attendances if _is_late(a)}
        leaves = rows('hr.leave', [('employee_id', 'in', ids), ('state', '=', 'validate'),
                                   ('request_date_from', '<=', last), ('request_date_to', '>=', first)])
        on_leave = {l.employee_id.id for l in leaves}
        absent = [p for p in team if p.id not in present and p.id not in on_leave]
        first_in = {}
        for a in attendances.sorted('check_in'):
            first_in.setdefault(a.employee_id.id, a)
        last_out = {}
        for a in attendances.sorted('check_in'):
            if a.check_out:
                last_out[a.employee_id.id] = a.check_out

        def person(p, extra=None):
            row = {'id': p.id, 'name': p.name, 'job': p.job_title or p.ff_designation_id.name or None,
                   'phone': p.mobile_phone or p.work_phone or None}
            row.update(extra or {})
            return row

        attendance = {
            'present': [person(p, {
                'in_at': to_iso(first_in[p.id].check_in), 'late': p.id in late,
                'late_minutes': _get_late_minutes(first_in[p.id]) if p.id in late else 0,
                'out_at': to_iso(last_out[p.id]) if last_out.get(p.id) else None,
                'place': getattr(first_in[p.id], 'ff_in_address', None) or None,
            }) for p in team if p.id in present],
            'late': [person(p, {'in_at': to_iso(first_in[p.id].check_in),
                                'late_minutes': _get_late_minutes(first_in[p.id]),
                                'place': getattr(first_in[p.id], 'ff_in_address', None) or None})
                     for p in team if p.id in late],
            'absent': [person(p) for p in absent],
            'leave': [person(p) for p in team if p.id in on_leave],
        }

        # ---- the team's beat plan
        lines = rows('ff.route.plan.customer', [('day_id.employee_id', 'in', ids), ('day_id.date', '>=', first),
                                                ('day_id.date', '<=', last), ('selected', '=', True)])
        planned = len(lines)
        if lines and 'status' in lines._fields:
            visited = len(lines.filtered(lambda l: l.status == 'visited'))
        else:
            visited = len(lines.filtered(lambda l: l.visit_id))
        cancelled = len(lines.filtered(lambda l: getattr(l, 'status', '') == 'cancelled')) \
            if lines and 'status' in lines._fields else 0
        per_person = {}
        for line in lines:
            who = line.day_id.employee_id
            row = per_person.setdefault(who.id, {'employee': ref(who), 'planned': 0, 'visited': 0, 'beats': set()})
            row['planned'] += 1
            row['visited'] += 1 if (line.status == 'visited' if 'status' in line._fields else line.visit_id) else 0
            if line.day_id.beat_id:
                row['beats'].add(line.day_id.beat_id.name)
        beat_plan = {
            'planned': planned, 'visited': visited, 'cancelled': cancelled,
            'pending': max(planned - visited - cancelled, 0),
            'people': [dict(r, beats=sorted(r['beats'])) for r in sorted(per_person.values(),
                                                                        key=lambda r: r['employee']['name'])],
        }

        # ---- overdue money, split into outlets and distributors
        overdue = {'total': 0.0, 'outlet': 0.0, 'distributor': 0.0, 'items': []}
        if 'account.move' in env:
            partners = env['res.partner'].sudo().search(client_domain(employee))
            families = partners.mapped('commercial_partner_id')
            if families:
                moves = env['account.move'].sudo().search([
                    ('move_type', '=', 'out_invoice'), ('state', '=', 'posted'),
                    ('payment_state', 'in', ('not_paid', 'partial')), ('invoice_date_due', '<', today),
                    ('partner_id', 'child_of', families.ids), ('company_id', '=', employee.company_id.id)])
                by_customer = {}
                for move in moves:
                    customer = move.partner_id.commercial_partner_id
                    kind = 'distributor' if getattr(customer, 'ff_category_type', '') == 'distributor' else 'outlet'
                    amount = move.amount_residual
                    overdue[kind] += amount
                    overdue['total'] += amount
                    row = by_customer.setdefault(customer.id, {
                        'customer': ref(customer), 'kind': kind, 'amount': 0.0, 'invoices': 0, 'days': 0,
                        'employee': move.invoice_user_id.name or None})
                    row['amount'] += amount
                    row['invoices'] += 1
                    row['days'] = max(row['days'], (today - move.invoice_date_due).days)
                overdue['items'] = sorted(by_customer.values(), key=lambda r: -r['amount'])[:100]
        overdue = {k: (round(v, 2) if isinstance(v, float) else v) for k, v in overdue.items()}
        for item in overdue['items']:
            item['amount'] = round(item['amount'], 2)

        # ---- tasks I gave
        tasks = rows('ff.task', ['|', ('assigned_by_employee_id', '=', employee.id),
                                 ('assigned_by_id', '=', employee.user_id.id or 0)], order='date_deadline, id desc', limit=200)
        pending = tasks.filtered(lambda t: t.state in ('todo', 'in_progress'))
        done = tasks.filtered(lambda t: t.state == 'done')
        late_tasks = pending.filtered('is_overdue') if 'is_overdue' in tasks._fields else pending.browse()
        shown = (late_tasks | pending)[:5]
        task_block = {
            'pending': len(pending), 'done': len(done), 'overdue': len(late_tasks),
            'latest': [{'id': t.id, 'name': t.name, 'to': t.employee_id.name,
                        'due': t.date_deadline.isoformat() if t.date_deadline else None,
                        'status': 'overdue' if t in late_tasks else 'pending'} for t in shown],
        }

        # ---- what needs a manager's eye
        alerts = []
        tomorrow = today + timedelta(days=1)
        planned_tomorrow = {p.employee_id.id for p in rows('ff.beat.plan', [('employee_id', 'in', ids),
                                                                            ('date', '=', tomorrow)])}
        missing_plan = [p.name for p in team if p.id not in planned_tomorrow]
        if missing_plan:
            alerts.append({'key': 'beat_not_planned', 'title': "Tomorrow's beat not planned",
                           'names': missing_plan[:8], 'people': missing_plan[:8], 'count': len(missing_plan)})
        y_start, y_end = employee._ff_day_bounds(today - timedelta(days=1))
        missed = rows('hr.attendance', [('employee_id', 'in', ids), ('check_in', '>=', y_start),
                                        ('check_in', '<', y_end), ('check_out', '=', False)])
        if missed:
            names = sorted({a.employee_id.name for a in missed})
            alerts.append({'key': 'missed_checkout', 'title': 'Missed check-out yesterday',
                           'names': names[:8], 'people': names[:8], 'count': len(names)})
        unsent = rows('ff.expense.claim', [('employee_id', 'in', ids), ('state', '=', 'draft')])
        if unsent:
            names = sorted({c.employee_id.name for c in unsent})
            alerts.append({'key': 'expenses_not_sent', 'title': 'Expenses not sent (Mon 10 am)',
                           'names': names[:8], 'people': names[:8], 'count': len(names)})

        return ok({
            'period': period, 'from': first.isoformat(), 'to': last.isoformat(),
            'currency': employee.company_id.currency_id.name,
            'team_size': len(team),
            'attendance': {k: {'count': len(v), 'people': v} for k, v in attendance.items()},
            'beat_plan': beat_plan,
            'overdue': overdue,
            'tasks': task_block,
            'alerts': alerts,
        })
