"""The report behind each panel section.

Every one answers the same shape - a few headline numbers, a series to draw,
and the rows behind them - so the panel can render them with one set of parts.
Sections whose module is absent simply return nothing and are not shown.
"""
import calendar
from datetime import timedelta

from odoo import api, fields, models

from odoo.addons.ff_base.tools import to_iso


class FfDashboardReports(models.AbstractModel):
    _inherit = 'ff.dashboard'

    # ------------------------------------------------------------------
    # Attendance
    # ------------------------------------------------------------------
    @api.model
    def ff_attendance_report(self, period='month', filters=None):
        employees = self._ff_filtered_employees(filters)
        today = self._ff_today()
        start, end = self._ff_range(period, filters)
        start_dt, end_dt = self._ff_day_range(start)[0], self._ff_day_range(end)[1]

        attendances = self.env['hr.attendance'].sudo().search([
            ('employee_id', 'in', employees.ids),
            ('check_in', '>=', start_dt), ('check_in', '<', end_dt)], order='check_in')
        days = (end - start).days + 1
        worked = sum(attendances.mapped('worked_hours'))
        late = attendances.filtered(lambda a: a.ff_late_minutes > 0) if attendances else attendances

        by_day = {}
        for attendance in attendances:
            day = fields.Date.to_date(attendance.check_in)
            row = by_day.setdefault(day, {'present': set(), 'hours': 0.0, 'late': 0})
            row['present'].add(attendance.employee_id.id)
            row['hours'] += attendance.worked_hours
            row['late'] += 1 if attendance.ff_late_minutes else 0

        series = []
        for index in range(days):
            day = start + timedelta(days=index)
            row = by_day.get(day, {'present': set(), 'hours': 0.0, 'late': 0})
            series.append({
                'day': day.isoformat(),
                'label': day.strftime('%d-%m'),
                'present': len(row['present']),
                'absent': 0 if day > today else max(len(employees) - len(row['present']), 0),
                'late': row['late'],
                'hours': round(row['hours'] / (len(row['present']) or 1), 2),
            })

        muster = []
        for employee in employees.sorted('name'):
            own = attendances.filtered(lambda a, e=employee: a.employee_id == e)
            present_days = len({fields.Date.to_date(a.check_in) for a in own})
            muster.append({
                'id': employee.id,
                'name': employee.name,
                'code': employee.ff_employee_code or '',
                'avatar': '/web/image/hr.employee/%s/avatar_128' % employee.id,
                'present': present_days,
                'absent': max(days - present_days, 0),
                'late': len(own.filtered(lambda a: a.ff_late_minutes > 0)),
                'hours': round(sum(own.mapped('worked_hours')), 1),
                'avg_hours': round(sum(own.mapped('worked_hours')) / present_days, 1) if present_days else 0.0,
                'last_in': to_iso(own[-1:].check_in) if own else False,
            })
        muster.sort(key=lambda row: -row['present'])

        return {
            'period': period,
            'period_label': self.ff_period_label(period, filters),
            'days': days,
            'employee_ids': employees.ids,
            'start': start.isoformat(),
            'end': end.isoformat(),
            'kpis': {
                'headcount': len(employees),
                'present_today': len({a.employee_id.id for a in attendances
                                      if fields.Date.to_date(a.check_in) == today}),
                'punches': len(attendances),
                'late': len(late),
                'hours': round(worked, 1),
                'avg_hours': round(worked / len(attendances), 1) if attendances else 0.0,
            },
            'series': series,
            'rows': muster,
        }

    # ------------------------------------------------------------------
    # Leaves, on Odoo's own Time Off
    # ------------------------------------------------------------------
    @api.model
    def ff_leaves_report(self, period='month', filters=None):
        if 'hr.leave' not in self.env:
            return None
        employees = self._ff_filtered_employees(filters)
        today = self._ff_today()
        start, end = self._ff_range(period, filters)
        Leave = self.env['hr.leave'].sudo()

        leaves = Leave.search([
            ('employee_id', 'in', employees.ids),
            ('date_from', '<', self._ff_day_range(max(end, today + timedelta(days=60)))[1]),
            ('date_to', '>=', self._ff_day_range(start)[0]),
        ], order='date_from')
        off_today = leaves.filtered(
            lambda leave: leave.state == 'validate'
            and fields.Date.to_date(leave.date_from) <= today <= fields.Date.to_date(leave.date_to))

        by_type = {}
        for leave in leaves.filtered(lambda l: l.state in ('confirm', 'validate1', 'validate', 'refuse')):
            key = leave.holiday_status_id
            row = by_type.setdefault(key.id, {'id': key.id, 'name': key.name, 'days': 0.0, 'count': 0,
                                              'approved': 0, 'pending': 0, 'refused': 0})
            if leave.state == 'refuse':
                row['refused'] += 1
                continue
            row['days'] += leave.number_of_days
            row['count'] += 1
            row['approved' if leave.state == 'validate' else 'pending'] += 1

        rows = [{
            'id': leave.id,
            'employee': leave.employee_id.name,
            'avatar': '/web/image/hr.employee/%s/avatar_128' % leave.employee_id.id,
            'type': leave.holiday_status_id.name,
            'from': leave.date_from and fields.Date.to_date(leave.date_from).isoformat(),
            'to': leave.date_to and fields.Date.to_date(leave.date_to).isoformat(),
            'days': leave.number_of_days,
            'state': leave.state,
            'reason': leave.private_name or leave.name or '',
        } for leave in leaves]

        return {
            'period': period,
            'period_label': self.ff_period_label(period, filters),
            'employee_ids': employees.ids,
            'start': start.isoformat(),
            'end': end.isoformat(),
            'kpis': {
                'pending': len(leaves.filtered(lambda l: l.state in ('confirm', 'validate1'))),
                'approved': len(leaves.filtered(lambda l: l.state == 'validate')),
                'refused': len(leaves.filtered(lambda l: l.state == 'refuse')),
                'off_today': len(off_today),
                'days': round(sum(leaves.filtered(lambda l: l.state == 'validate').mapped('number_of_days')), 1),
            },
            'by_type': sorted(by_type.values(), key=lambda row: -row['days']),
            'off_today': [{'id': leave.employee_id.id, 'name': leave.employee_id.name,
                           'type': leave.holiday_status_id.name,
                           'until': fields.Date.to_date(leave.date_to).isoformat()} for leave in off_today],
            'rows': rows,
        }

    # ------------------------------------------------------------------
    # Expenses
    # ------------------------------------------------------------------
    @api.model
    def ff_expense_report(self, period='month', filters=None):
        if 'ff.expense.claim' not in self.env:
            return None
        employees = self._ff_filtered_employees(filters)
        start, end = self._ff_range(period, filters)
        Claim = self.env['ff.expense.claim'].sudo()
        claims = Claim.search([
            ('employee_id', 'in', employees.ids),
            ('date', '>=', start), ('date', '<=', end)], order='date desc')

        def bucket(state):
            selected = claims.filtered(lambda claim, s=state: claim.state == s)
            return {'amount': round(sum(selected.mapped('amount')), 2), 'count': len(selected)}

        by_category = {}
        for claim in claims:
            key = claim.category_id
            row = by_category.setdefault(key.id, {'id': key.id, 'name': key.name or 'Uncategorised',
                                                  'amount': 0.0, 'count': 0})
            row['amount'] += claim.amount
            row['count'] += 1

        by_employee = {}
        for claim in claims:
            key = claim.employee_id
            row = by_employee.setdefault(key.id, {'id': key.id, 'name': key.name, 'amount': 0.0, 'count': 0})
            row['amount'] += claim.amount
            row['count'] += 1

        return {
            'period': period,
            'period_label': self.ff_period_label(period, filters),
            'employee_ids': employees.ids,
            'start': start.isoformat(),
            'end': end.isoformat(),
            'currency': self.env.company.currency_id.symbol or '',
            'kpis': {
                'total': round(sum(claims.mapped('amount')), 2),
                'count': len(claims),
                'draft': bucket('draft'),
                'submitted': bucket('submitted'),
                'approved': bucket('approved'),
                'rejected': bucket('rejected'),
                'per_head': round(sum(claims.mapped('amount')) / len(employees), 2) if employees else 0.0,
            },
            'by_category': sorted(by_category.values(), key=lambda row: -row['amount']),
            'by_employee': sorted(by_employee.values(), key=lambda row: -row['amount'])[:10],
            'rows': [{
                'id': claim.id,
                'date': claim.date.isoformat(),
                'employee': claim.employee_id.name,
                'employee_id': claim.employee_id.id,
                'avatar': '/web/image/hr.employee/%s/avatar_128' % claim.employee_id.id,
                'category': claim.category_id.name or '',
                'partner': claim.partner_id.display_name or '',
                'amount': round(claim.amount, 2),
                'state': claim.state,
                'receipts': claim.receipt_count,
                'note': claim.note or '',
            } for claim in claims[:200]],
        }

    # ------------------------------------------------------------------
    # Orders, and demand when that flow is on
    # ------------------------------------------------------------------
    @api.model
    def ff_order_report(self, period='month', filters=None):
        employees = self._ff_filtered_employees(filters)
        start, end = self._ff_range(period, filters)
        start_dt = self._ff_day_range(start)[0]
        end_dt = self._ff_day_range(end)[1]
        flow = self.env['ir.config_parameter'].sudo().get_param('ff_base.order_flow') or 'direct'

        build = self._demand_report if flow == 'demand' and 'ff.demand' in self.env else self._sale_report
        report = build(employees, start, start_dt, end, end_dt, period, flow)
        # The same length of time just before, for the "vs last period" chips.
        length = (end - start).days + 1
        prev_end = start - timedelta(days=1)
        prev_start = start - timedelta(days=length)
        previous = build(employees, prev_start, self._ff_day_range(prev_start)[0],
                         prev_end, self._ff_day_range(prev_end)[1], period, flow)
        report['previous'] = previous['kpis']
        report['period_label'] = self.ff_period_label(period, filters)
        return report

    def _sale_report(self, employees, start, start_dt, end, end_dt, period, flow):
        orders = self.env['sale.order'].sudo().search([
            ('ff_employee_id', 'in', employees.ids),
            ('date_order', '>=', start_dt), ('date_order', '<', end_dt)], order='date_order desc')
        total = sum(orders.mapped('amount_total'))
        series = self._daily_series(start, end, orders, lambda order: fields.Date.to_date(order.date_order),
                                    lambda order: order.amount_total)
        return {
            'flow': flow,
            'period': period,
            'employee_ids': employees.ids,
            'start': start.isoformat(),
            'currency': self.env.company.currency_id.symbol or '',
            'kpis': {
                'total': round(total, 2),
                'count': len(orders),
                'average': round(total / len(orders), 2) if orders else 0.0,
                'confirmed': len(orders.filtered(lambda order: order.state == 'sale')),
                'outlets': len(orders.mapped('partner_id')),
            },
            'series': series,
            'by_employee': self._group_amounts(orders, lambda order: order.ff_employee_id,
                                               lambda order: order.amount_total),
            'by_product': self._product_amounts(orders.mapped('order_line')),
            'rows': [{
                'id': order.id,
                'name': order.name,
                'date': to_iso(order.date_order),
                'employee': order.ff_employee_id.name or '',
                'partner': order.partner_id.display_name,
                'amount': round(order.amount_total, 2),
                'state': order.state,
            } for order in orders[:200]],
        }

    def _demand_report(self, employees, start, start_dt, end, end_dt, period, flow):
        demands = self.env['ff.demand'].sudo().search([
            ('employee_id', 'in', employees.ids),
            ('date', '>=', start_dt), ('date', '<', end_dt)], order='date desc')
        total = sum(demands.mapped('amount_total'))
        series = self._daily_series(start, end, demands, lambda demand: fields.Date.to_date(demand.date),
                                    lambda demand: demand.amount_total)
        pending = demands.filtered(lambda demand: demand.state in ('submitted', 'partial'))
        return {
            'flow': flow,
            'period': period,
            'employee_ids': employees.ids,
            'start': start.isoformat(),
            'currency': self.env.company.currency_id.symbol or '',
            'kpis': {
                'total': round(total, 2),
                'count': len(demands),
                'average': round(total / len(demands), 2) if demands else 0.0,
                'pending': len(pending),
                'pending_value': round(sum(pending.mapped('amount_total')), 2),
                'outlets': len(demands.mapped('partner_id')),
            },
            'series': series,
            'by_employee': self._group_amounts(demands, lambda demand: demand.employee_id,
                                               lambda demand: demand.amount_total),
            'by_distributor': self._group_amounts(demands, lambda demand: demand.distributor_id,
                                                  lambda demand: demand.amount_total),
            'by_product': self._demand_products(demands.mapped('line_ids')),
            'rows': [{
                'id': demand.id,
                'name': demand.name,
                'date': to_iso(demand.date),
                'employee': demand.employee_id.name,
                'partner': demand.partner_id.display_name,
                'distributor': demand.distributor_id.display_name or '',
                'amount': round(demand.amount_total, 2),
                'state': demand.state,
                'quoted_percent': demand.quoted_ratio,
            } for demand in demands[:200]],
        }

    # -- little helpers the reports share --------------------------------
    def _daily_series(self, start, end, records, day_of, amount_of):
        totals = {}
        counts = {}
        outlets = {}
        for record in records:
            day = day_of(record)
            totals[day] = totals.get(day, 0.0) + amount_of(record)
            counts[day] = counts.get(day, 0) + 1
            if 'partner_id' in record._fields and record.partner_id:
                outlets.setdefault(day, set()).add(record.partner_id.id)
        series = []
        for index in range((end - start).days + 1):
            day = start + timedelta(days=index)
            series.append({'day': day.isoformat(), 'label': day.strftime('%d-%m'),
                           'amount': round(totals.get(day, 0.0), 2), 'count': counts.get(day, 0),
                           'outlets': len(outlets.get(day, ()))})
        return series

    def _group_amounts(self, records, key_of, amount_of, limit=8):
        rows = {}
        for record in records:
            key = key_of(record)
            if not key:
                continue
            row = rows.setdefault(key.id, {'id': key.id, 'name': key.display_name, 'amount': 0.0, 'count': 0})
            row['amount'] += amount_of(record)
            row['count'] += 1
        for row in rows.values():
            row['amount'] = round(row['amount'], 2)
        return sorted(rows.values(), key=lambda row: -row['amount'])[:limit]

    def _product_amounts(self, lines, limit=8):
        rows = {}
        for line in lines.filtered('product_id'):
            row = rows.setdefault(line.product_id.id, {
                'id': line.product_id.id, 'name': line.product_id.display_name,
                'quantity': 0.0, 'amount': 0.0})
            row['quantity'] += line.product_uom_qty
            row['amount'] += line.price_subtotal
        for row in rows.values():
            row['amount'] = round(row['amount'], 2)
        return sorted(rows.values(), key=lambda row: -row['amount'])[:limit]

    def _demand_products(self, lines, limit=8):
        rows = {}
        for line in lines.filtered('product_id'):
            row = rows.setdefault(line.product_id.id, {
                'id': line.product_id.id, 'name': line.product_id.display_name,
                'quantity': 0.0, 'amount': 0.0, 'quoted': 0.0})
            row['quantity'] += line.quantity
            row['quoted'] += line.quoted_quantity
            row['amount'] += line.subtotal
        for row in rows.values():
            row['amount'] = round(row['amount'], 2)
        return sorted(rows.values(), key=lambda row: -row['quantity'])[:limit]

    # ------------------------------------------------------------------
    # Attendance as a month calendar
    # ------------------------------------------------------------------
    @api.model
    def ff_attendance_calendar(self, month=None, filters=None):
        """A month of boxes: one cell per day, one small box per employee inside.

        Green means present, amber late, red absent, and days outside the month
        or still to come are left empty rather than counted as absence.
        """
        employees = self._ff_filtered_employees(filters)
        today = self._ff_today()
        first = fields.Date.to_date(month) if month else today
        first = first.replace(day=1)
        last_day = calendar.monthrange(first.year, first.month)[1]
        last = first.replace(day=last_day)

        attendances = self.env['hr.attendance'].sudo().search([
            ('employee_id', 'in', employees.ids),
            ('check_in', '>=', self._ff_day_range(first)[0]),
            ('check_in', '<', self._ff_day_range(last)[1]),
        ], order='check_in')

        by_day = {}
        for attendance in attendances:
            day = fields.Date.to_date(attendance.check_in)
            row = by_day.setdefault(day, {})
            entry = row.setdefault(attendance.employee_id.id, {'hours': 0.0, 'late': 0, 'first': attendance.check_in})
            entry['hours'] += attendance.worked_hours
            entry['late'] += 1 if attendance.ff_late_minutes else 0
            entry['first'] = min(entry['first'], attendance.check_in)

        leave_days = self._ff_leave_days(employees, first, last)

        weeks, week = [], []
        # Monday-first grid, padded so the month starts in the right column.
        lead = first.weekday()
        for _ in range(lead):
            week.append(None)
        for number in range(1, last_day + 1):
            day = first.replace(day=number)
            week.append(self._calendar_day(day, today, employees, by_day.get(day, {}), leave_days))
            if len(week) == 7:
                weeks.append(week)
                week = []
        if week:
            week += [None] * (7 - len(week))
            weeks.append(week)

        present_days = sum(cell['present'] for row in weeks for cell in row if cell)
        working_days = len([cell for row in weeks for cell in row if cell and not cell['future']])
        return {
            'month': first.strftime('%Y-%m-%d'),
            'label': first.strftime('%B %Y'),
            'employees': [{'id': employee.id, 'name': employee.name} for employee in employees.sorted('name')],
            'weeks': weeks,
            'totals': {
                'headcount': len(employees),
                'present': present_days,
                'expected': working_days * len(employees),
                'late': sum(cell['late'] for row in weeks for cell in row if cell),
                'on_leave': sum(cell['leave'] for row in weeks for cell in row if cell),
            },
        }

    def _calendar_day(self, day, today, employees, punches, leave_days):
        boxes = []
        for employee in employees.sorted('name'):
            punch = punches.get(employee.id)
            if punch:
                status = 'late' if punch['late'] else 'present'
            elif employee.id in leave_days.get(day, set()):
                status = 'leave'
            elif day > today:
                status = 'future'
            else:
                status = 'absent'
            boxes.append({
                'id': employee.id,
                'name': employee.name,
                'status': status,
                'hours': round(punch['hours'], 1) if punch else 0.0,
                'at': to_iso(punch['first']) if punch else False,
            })
        return {
            'date': day.isoformat(),
            'day': day.day,
            'weekday': day.strftime('%a'),
            'today': day == today,
            'future': day > today,
            'present': len([box for box in boxes if box['status'] in ('present', 'late')]),
            'late': len([box for box in boxes if box['status'] == 'late']),
            'leave': len([box for box in boxes if box['status'] == 'leave']),
            'absent': len([box for box in boxes if box['status'] == 'absent']),
            'boxes': boxes,
        }

    def _ff_leave_days(self, employees, first, last):
        """Which employees were on approved leave on which day."""
        days = {}
        if 'hr.leave' not in self.env:
            return days
        leaves = self.env['hr.leave'].sudo().search([
            ('employee_id', 'in', employees.ids), ('state', '=', 'validate'),
            ('date_from', '<=', self._ff_day_range(last)[1]),
            ('date_to', '>=', self._ff_day_range(first)[0]),
        ])
        for leave in leaves:
            start = max(fields.Date.to_date(leave.date_from), first)
            end = min(fields.Date.to_date(leave.date_to), last)
            for index in range((end - start).days + 1):
                days.setdefault(start + timedelta(days=index), set()).add(leave.employee_id.id)
        return days
