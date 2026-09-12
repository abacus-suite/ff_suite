"""Numbers behind the Aixolo panel.

One call returns everything the dashboard draws, so the screen opens with a
single request. Modules that may not be installed (expenses, collections,
visit steps) are read only when their model is present.
"""
from datetime import timedelta

from odoo import api, fields, models

from odoo.addons.ff_base.tools import to_iso


def pct_change(today, yesterday):
    """Percent change, with the awkward zero cases spelled out."""
    if not yesterday:
        return 100.0 if today else 0.0
    return round((today - yesterday) / float(yesterday) * 100.0, 1)


class FfDashboard(models.AbstractModel):
    _name = 'ff.dashboard'
    _description = 'Aixolo Dashboard Data'

    # ------------------------------------------------------------------
    # Who the viewer may see
    # ------------------------------------------------------------------
    @api.model
    def _ff_employees(self):
        Employee = self.env['hr.employee'].sudo()
        company_domain = [('company_id', 'in', self.env.companies.ids)]
        if self.env.user.has_group('ff_base.group_ff_admin'):
            return Employee.search(company_domain)
        scope_ids = self.env.user.ff_scope_employee_ids()
        if scope_ids:
            return Employee.browse(scope_ids).exists()
        if self.env.user.has_group('ff_base.group_ff_manager'):
            return Employee.search(company_domain)
        return Employee.browse()

    def _ff_day_range(self, day):
        """UTC bounds of a local day, so counts match what people saw."""
        start = fields.Datetime.to_datetime('%s 00:00:00' % day)
        return start, start + timedelta(days=1)

    # ------------------------------------------------------------------
    # The whole payload
    # ------------------------------------------------------------------
    @api.model
    def ff_dashboard_data(self, period='month'):
        employees = self._ff_employees()
        today = fields.Date.context_today(self)
        yesterday = today - timedelta(days=1)
        start = self._period_start(today, period)
        return {
            'company': self.env.company.name,
            'currency': self.env.company.currency_id.symbol or self.env.company.currency_id.name,
            'today': today.isoformat(),
            'period': period,
            'period_label': {'today': 'Today', 'week': 'This Week', 'month': 'This Month'}.get(period, 'This Month'),
            'realtime': self._realtime(employees),
            'teams': self._teamwise(employees),
            'people': self._people(employees),
            'counters': self._counters(employees, today, yesterday),
            'working_hours': self._working_hours(employees, start, today),
            'visits': self._visit_status(employees, start),
            'expenses': self._expenses(employees, start),
            'collections': self._collections(employees, start),
            'orders': self._orders(employees, start),
        }

    def _period_start(self, today, period):
        if period == 'today':
            return today
        if period == 'week':
            return today - timedelta(days=today.weekday())
        return today.replace(day=1)

    # ------------------------------------------------------------------
    # Cards
    # ------------------------------------------------------------------
    def _realtime(self, employees):
        Status = self.env['ff.employee.status'].sudo()
        statuses = Status.search([('employee_id', 'in', employees.ids)])
        punched_in = statuses.filtered('punched_in')
        return {
            'total': len(employees),
            'punched_in': len(punched_in),
            'punched_out': len(employees) - len(punched_in),
            'inactive': len(punched_in.filtered('is_inactive')),
            'no_signal': len(punched_in.filtered(lambda s: s.is_signal_lost or not s.gps_on)),
            'low_battery': len(punched_in.filtered('is_low_battery')),
            'at_client': self.env['ff.visit'].sudo().search_count(
                [('employee_id', 'in', employees.ids), ('state', '=', 'ongoing')]),
        }

    def _teamwise(self, employees):
        Status = self.env['ff.employee.status'].sudo()
        rows = {}
        for employee in employees:
            team = employee.ff_team_id
            key = team.id or 0
            row = rows.setdefault(key, {'id': key, 'name': team.name or 'No team', 'in': 0, 'out': 0})
            row['out'] += 1  # corrected below once the status is known
        for status in Status.search([('employee_id', 'in', employees.ids), ('punched_in', '=', True)]):
            key = status.employee_id.ff_team_id.id or 0
            if key in rows:
                rows[key]['in'] += 1
                rows[key]['out'] -= 1
        return sorted(rows.values(), key=lambda row: (-row['in'], row['name']))

    def _people(self, employees):
        """The attendance list: who punched in, when, and where they were last seen."""
        Status = self.env['ff.employee.status'].sudo()
        statuses = {s.employee_id.id: s for s in Status.search([('employee_id', 'in', employees.ids)])}
        visits = {
            visit.employee_id.id: visit
            for visit in self.env['ff.visit'].sudo().search(
                [('employee_id', 'in', employees.ids), ('state', '=', 'ongoing')])
        }
        people = []
        for employee in employees:
            status = statuses.get(employee.id)
            visit = visits.get(employee.id)
            people.append({
                'id': employee.id,
                'name': employee.name,
                'code': employee.ff_employee_code or '',
                'team': employee.ff_team_id.name or '',
                'avatar': '/web/image/hr.employee/%s/avatar_128' % employee.id,
                'punched_in': bool(status and status.punched_in),
                'punched_at': to_iso(status.punched_in_at) if status else False,
                'last_ping_at': to_iso(status.last_ping_at) if status else False,
                'lat': status.latitude if status else 0.0,
                'lng': status.longitude if status else 0.0,
                'battery': status.battery if status else 0,
                'at_client': visit.partner_id.display_name if visit else '',
            })
        people.sort(key=lambda row: (not row['punched_in'], row['name'] or ''))
        return people

    def _counters(self, employees, today, yesterday):
        """Today against yesterday, the way the field measures a day."""
        Visit = self.env['ff.visit'].sudo()
        Partner = self.env['res.partner'].sudo()

        def day_count(model, date_field, day, extra=None):
            start, end = self._ff_day_range(day)
            domain = [(date_field, '>=', start), (date_field, '<', end)]
            if 'employee_id' in model._fields:
                domain.append(('employee_id', 'in', employees.ids))
            return model.search_count(domain + (extra or []))

        counters = {
            'visits': {
                'today': day_count(Visit, 'check_in_at', today),
                'yesterday': day_count(Visit, 'check_in_at', yesterday),
            },
            'new_clients': {
                'today': Partner.search_count([
                    ('ff_is_client', '=', True), ('ff_created_by_employee_id', 'in', employees.ids),
                    ('create_date', '>=', self._ff_day_range(today)[0]),
                ]),
                'yesterday': Partner.search_count([
                    ('ff_is_client', '=', True), ('ff_created_by_employee_id', 'in', employees.ids),
                    ('create_date', '>=', self._ff_day_range(yesterday)[0]),
                    ('create_date', '<', self._ff_day_range(yesterday)[1]),
                ]),
            },
        }
        if 'sale.order' in self.env:
            Order = self.env['sale.order'].sudo()
            counters['orders'] = {
                'today': Order.search_count([
                    ('ff_employee_id', 'in', employees.ids),
                    ('date_order', '>=', self._ff_day_range(today)[0]),
                ]),
                'yesterday': Order.search_count([
                    ('ff_employee_id', 'in', employees.ids),
                    ('date_order', '>=', self._ff_day_range(yesterday)[0]),
                    ('date_order', '<', self._ff_day_range(yesterday)[1]),
                ]),
            }
        if 'ff.form.response' in self.env:
            Response = self.env['ff.form.response'].sudo()
            counters['forms'] = {
                'today': day_count(Response, 'submitted_at', today),
                'yesterday': day_count(Response, 'submitted_at', yesterday),
            }
        photos_today = self.env['ir.attachment'].sudo().search_count([
            ('res_model', 'in', ['ff.visit', 'ff.visit.step.record', 'ff.expense.claim']),
            ('create_date', '>=', self._ff_day_range(today)[0]),
        ])
        photos_yesterday = self.env['ir.attachment'].sudo().search_count([
            ('res_model', 'in', ['ff.visit', 'ff.visit.step.record', 'ff.expense.claim']),
            ('create_date', '>=', self._ff_day_range(yesterday)[0]),
            ('create_date', '<', self._ff_day_range(yesterday)[1]),
        ])
        counters['photos'] = {'today': photos_today, 'yesterday': photos_yesterday}
        for row in counters.values():
            row['change'] = pct_change(row['today'], row['yesterday'])
        return counters

    def _working_hours(self, employees, start, today):
        """Average hours worked per day, for the bar chart."""
        Attendance = self.env['hr.attendance'].sudo()
        groups = Attendance._read_group(
            [('employee_id', 'in', employees.ids), ('check_in', '>=', self._ff_day_range(start)[0])],
            ['check_in:day'], ['worked_hours:sum', '__count'])
        rows = []
        for day, hours, count in groups:
            rows.append({
                'day': fields.Date.to_date(day).isoformat(),
                'label': fields.Date.to_date(day).strftime('%d-%m'),
                'hours': round((hours or 0.0) / (count or 1), 2),
            })
        rows.sort(key=lambda row: row['day'])
        return rows

    def _visit_status(self, employees, start):
        """Planned vs done for the period, the field's version of task status."""
        Visit = self.env['ff.visit'].sudo()
        start_dt = self._ff_day_range(start)[0]
        done = Visit.search_count([
            ('employee_id', 'in', employees.ids), ('check_in_at', '>=', start_dt), ('state', '=', 'done')])
        ongoing = Visit.search_count([
            ('employee_id', 'in', employees.ids), ('state', '=', 'ongoing')])
        planned = missed = 0
        if 'ff.route.plan.customer' in self.env:
            Line = self.env['ff.route.plan.customer'].sudo()
            planned = Line.search_count([
                ('employee_id', 'in', employees.ids), ('date', '>=', start), ('status', '=', 'planned')])
            missed = Line.search_count([
                ('employee_id', 'in', employees.ids), ('date', '>=', start), ('status', '=', 'missed')])
        return {'done': done, 'ongoing': ongoing, 'planned': planned, 'missed': missed,
                'total': done + ongoing + planned + missed}

    def _expenses(self, employees, start):
        if 'ff.expense.claim' not in self.env:
            return None
        Claim = self.env['ff.expense.claim'].sudo()
        groups = Claim._read_group(
            [('employee_id', 'in', employees.ids), ('date', '>=', start)], ['state'], ['amount:sum', '__count'])
        by_state = {state: {'amount': round(amount or 0.0, 2), 'count': count} for state, amount, count in groups}
        total = round(sum(row['amount'] for row in by_state.values()), 2)
        return {
            'total': total,
            'count': sum(row['count'] for row in by_state.values()),
            'draft': by_state.get('draft', {'amount': 0, 'count': 0}),
            'submitted': by_state.get('submitted', {'amount': 0, 'count': 0}),
            'approved': by_state.get('approved', {'amount': 0, 'count': 0}),
            'rejected': by_state.get('rejected', {'amount': 0, 'count': 0}),
        }

    def _collections(self, employees, start):
        if 'ff.collection' not in self.env:
            return None
        Collection = self.env['ff.collection'].sudo()
        groups = Collection._read_group(
            [('employee_id', 'in', employees.ids), ('date', '>=', self._ff_day_range(start)[0]),
             ('state', '!=', 'cancelled')],
            ['state'], ['amount:sum', '__count'])
        by_state = {state: {'amount': round(amount or 0.0, 2), 'count': count} for state, amount, count in groups}
        with_staff = by_state.get('collected', {'amount': 0, 'count': 0})
        return {
            'total': round(sum(row['amount'] for row in by_state.values()), 2),
            'count': sum(row['count'] for row in by_state.values()),
            'with_staff': with_staff,
            'submitted': by_state.get('submitted', {'amount': 0, 'count': 0}),
            'received': by_state.get('received', {'amount': 0, 'count': 0}),
        }

    def _orders(self, employees, start):
        if 'sale.order' not in self.env:
            return None
        Order = self.env['sale.order'].sudo()
        start_dt = self._ff_day_range(start)[0]
        groups = Order._read_group(
            [('ff_employee_id', 'in', employees.ids), ('date_order', '>=', start_dt)],
            ['ff_employee_id'], ['amount_total:sum', '__count'])
        top = sorted(
            [{'id': employee.id, 'name': employee.display_name, 'amount': round(amount or 0.0, 2), 'count': count}
             for employee, amount, count in groups],
            key=lambda row: -row['amount'])[:6]
        return {
            'total': round(sum(row['amount'] for row in top), 2),
            'count': sum(row['count'] for row in top),
            'top': top,
        }
