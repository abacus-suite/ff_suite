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

    @api.model
    def _ff_filtered_employees(self, filters=None):
        """The scope, narrowed by whatever the panel's filters are set to."""
        employees = self._ff_employees()
        filters = filters or {}
        employee_id = filters.get('employee_id')
        if employee_id:
            employees = employees.filtered(lambda e, i=int(employee_id): e.id == i)
        department_id = filters.get('department_id')
        if department_id:
            employees = employees.filtered(lambda e, i=int(department_id): e.department_id.id == i)
        team_id = filters.get('team_id')
        if team_id:
            employees = employees.filtered(lambda e, i=int(team_id): e.ff_team_id.id == i)
        return employees

    @api.model
    def ff_filter_options(self):
        """What the filter dropdowns offer: only what the viewer may see."""
        employees = self._ff_employees()
        return {
            'employees': [{'id': employee.id, 'name': employee.name,
                           'code': employee.ff_employee_code or ''}
                          for employee in employees.sorted('name')],
            'departments': [{'id': department.id, 'name': department.name}
                            for department in employees.mapped('department_id').sorted('name')],
            'teams': [{'id': team.id, 'name': team.name}
                      for team in employees.mapped('ff_team_id').sorted('name')],
        }

    def _ff_day_range(self, day):
        """UTC bounds of a local day, so counts match what people saw."""
        start = fields.Datetime.to_datetime('%s 00:00:00' % day)
        return start, start + timedelta(days=1)

    # ------------------------------------------------------------------
    # The whole payload
    # ------------------------------------------------------------------
    @api.model
    def ff_dashboard_data(self, period='month', filters=None):
        employees = self._ff_filtered_employees(filters)
        today = fields.Date.context_today(self)
        yesterday = today - timedelta(days=1)
        start, end = self._ff_range(period, filters)
        return {
            'company': self.env.company.name,
            'currency': self.env.company.currency_id.symbol or self.env.company.currency_id.name,
            'today': today.isoformat(),
            'period': period,
            'period_label': self.ff_period_label(period, filters),
            'realtime': self._realtime(employees),
            'teams': self._teamwise(employees),
            'people': self._people(employees),
            'counters': self._counters(employees, today, yesterday),
            'working_hours': self._working_hours(employees, start, end),
            'visits': self._visit_status(employees, start),
            'expenses': self._expenses(employees, start),
            'collections': self._collections(employees, start),
            'orders': self._orders(employees, start),
            'geocode_problem': self.env['ir.config_parameter'].sudo().get_param(
                'ff_base.geocode_problem') or '',
        }

    def _period_start(self, today, period):
        return self._ff_range(period)[0]

    @api.model
    def _ff_range(self, period='month', filters=None):
        """The two dates a report covers.

        The named periods are the everyday ones; "custom" takes the dates the
        filter bar carries, which is how last month, a quarter or any stretch of
        days is asked for. A range that runs backwards is turned around rather
        than returning nothing.
        """
        today = fields.Date.context_today(self)
        filters = filters or {}
        if period == 'custom' or filters.get('date_from') or filters.get('date_to'):
            start = fields.Date.to_date(filters.get('date_from')) or today.replace(day=1)
            end = fields.Date.to_date(filters.get('date_to')) or today
            if end < start:
                start, end = end, start
            return start, end
        if period == 'today':
            return today, today
        if period == 'yesterday':
            return today - timedelta(days=1), today - timedelta(days=1)
        if period == 'week':
            return today - timedelta(days=today.weekday()), today
        if period == 'last_week':
            monday = today - timedelta(days=today.weekday() + 7)
            return monday, monday + timedelta(days=6)
        if period == 'last_month':
            first = today.replace(day=1)
            last_month_end = first - timedelta(days=1)
            return last_month_end.replace(day=1), last_month_end
        if period == 'quarter':
            first_month = 3 * ((today.month - 1) // 3) + 1
            return today.replace(month=first_month, day=1), today
        if period == 'year':
            return today.replace(month=1, day=1), today
        return today.replace(day=1), today

    @api.model
    def ff_period_label(self, period='month', filters=None):
        start, end = self._ff_range(period, filters)
        if start == end:
            return start.strftime('%d %b %Y')
        return '%s - %s' % (start.strftime('%d %b'), end.strftime('%d %b %Y'))

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
        rows = Status.search([('employee_id', 'in', employees.ids)])
        if hasattr(rows, 'ff_resolve_addresses'):
            rows.ff_resolve_addresses()
        statuses = {row.employee_id.id: row for row in rows}
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
                'address': (status.address or '') if status and 'address' in status._fields else '',
                'accuracy': round(status.accuracy or 0.0) if status else 0,
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

    # ------------------------------------------------------------------
    # Live Location: one employee's day, for the tabs under their card
    # ------------------------------------------------------------------
    @api.model
    def ff_employee_day(self, employee_id, day=None):
        """What this person did today: visits, orders and forms."""
        employee = self.env['hr.employee'].sudo().browse(int(employee_id)).exists()
        if not employee or employee not in self._ff_employees():
            return {'visits': [], 'orders': [], 'forms': []}
        day = fields.Date.to_date(day) if day else fields.Date.context_today(self)
        start, end = self._ff_day_range(day)
        return {
            'employee_id': employee.id,
            'date': day.isoformat(),
            'visits': self._day_visits(employee, start, end),
            'orders': self._day_orders(employee, start, end),
            'forms': self._day_forms(employee, start, end),
        }

    def _day_visits(self, employee, start, end):
        visits = self.env['ff.visit'].sudo().search([
            ('employee_id', '=', employee.id), ('check_in_at', '>=', start), ('check_in_at', '<', end),
        ], order='check_in_at')
        return [{
            'id': visit.id,
            'client': visit.partner_id.display_name,
            'state': visit.state,
            'check_in_at': to_iso(visit.check_in_at),
            'check_out_at': to_iso(visit.check_out_at),
            'duration_min': visit.duration_min,
            'outcome': visit.outcome_id.name or visit.outcome or '',
            'inside_geofence': visit.inside_geofence,
        } for visit in visits]

    def _day_orders(self, employee, start, end):
        if 'sale.order' not in self.env:
            return []
        orders = self.env['sale.order'].sudo().search([
            ('ff_employee_id', '=', employee.id), ('date_order', '>=', start), ('date_order', '<', end),
        ], order='date_order')
        return [{
            'id': order.id,
            'name': order.name,
            'client': order.partner_id.display_name,
            'amount': round(order.amount_total, 2),
            'state': order.state,
            'at': to_iso(order.date_order),
        } for order in orders]

    def _day_forms(self, employee, start, end):
        if 'ff.form.response' not in self.env:
            return []
        responses = self.env['ff.form.response'].sudo().search([
            ('employee_id', '=', employee.id), ('submitted_at', '>=', start), ('submitted_at', '<', end),
        ], order='submitted_at')
        return [{
            'id': response.id,
            'name': response.form_id.name,
            'client': response.partner_id.display_name or '',
            'at': to_iso(response.submitted_at),
        } for response in responses]
