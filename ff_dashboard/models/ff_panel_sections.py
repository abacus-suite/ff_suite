"""Panel sections drawn from one generic shape - visits, collections, demands -
and the Excel export every report section shares.

Generic shape: ``tiles`` (headline numbers, each able to open its records),
``charts`` (bar/line data) and ``columns`` + ``rows`` for the table. The panel
renders any section that answers in this shape with the same template.
"""
import base64
from datetime import timedelta

from odoo import api, fields, models

# Panel section -> the app report that holds the same rows for Excel.
EXPORT_KEYS = {
    'attendance': 'attendance',
    'leaves': 'leaves',
    'expenses': 'expenses',
    'orders': 'orders',
    'visits': 'visits',
    'collections': 'collections',
    'demands': 'demands',
    'targets': 'targets',
}


class FfDashboardSections(models.AbstractModel):
    _inherit = 'ff.dashboard'

    # ------------------------------------------------------------------
    # Shared frame
    # ------------------------------------------------------------------
    def _generic(self, period, filters, model, employee_field, date_field):
        employees = self._ff_filtered_employees(filters)
        start, end = self._ff_range(period, filters)
        return employees, start, end, {
            'generic': True,
            'period': period,
            'period_label': self.ff_period_label(period, filters),
            'employee_ids': employees.ids,
            'start': start.isoformat(),
            'end': end.isoformat(),
            'currency': self.env.company.currency_id.symbol or '',
            'model': model,
            'employee_field': employee_field,
            'date_field': date_field,
        }

    @staticmethod
    def _tile(label, value, color, sub=None, money=False, domain=None):
        return {'label': label, 'value': value, 'color': color, 'sub': sub, 'money': money, 'domain': domain or []}

    @staticmethod
    def _bar(title, icon, rows, key='amount', money=True):
        return {'title': title, 'icon': icon, 'type': 'bar', 'horizontal': True, 'money': money,
                'labels': [row['name'] for row in rows], 'values': [round(row[key], 2) for row in rows]}

    def _per_day(self, title, icon, start, end, records, day_of, value_of, money=False):
        totals = {}
        for record in records:
            day = day_of(record)
            totals[day] = totals.get(day, 0.0) + value_of(record)
        days = [start + timedelta(days=i) for i in range((end - start).days + 1)]
        return {'title': title, 'icon': icon, 'type': 'line', 'horizontal': False, 'money': money,
                'labels': [day.strftime('%d-%m') for day in days],
                'values': [round(totals.get(day, 0.0), 2) for day in days]}

    @staticmethod
    def _count_by(records, key_of, limit=10):
        rows = {}
        for record in records:
            key = key_of(record)
            if key:
                row = rows.setdefault(key.id, {'id': key.id, 'name': key.display_name, 'count': 0.0, 'amount': 0.0})
                row['count'] += 1
        return sorted(rows.values(), key=lambda row: -row['count'])[:limit]

    @staticmethod
    def _sum_by(records, key_of, amount_of, limit=10):
        rows = {}
        for record in records:
            key = key_of(record)
            if key:
                row = rows.setdefault(key.id, {'id': key.id, 'name': key.display_name, 'count': 0.0, 'amount': 0.0})
                row['amount'] += amount_of(record)
                row['count'] += 1
        return sorted(rows.values(), key=lambda row: -row['amount'])[:limit]

    def _local_day(self, employee, value):
        return employee._ff_to_local(value).date() if value else None

    # ------------------------------------------------------------------
    # Visits
    # ------------------------------------------------------------------
    @api.model
    def ff_visit_report(self, period='month', filters=None):
        employees, start, end, report = self._generic(period, filters, 'ff.visit', 'employee_id', 'check_in_at')
        low, high = self._ff_day_range(start)[0], self._ff_day_range(end)[1]
        visits = self.env['ff.visit'].sudo().search([
            ('employee_id', 'in', employees.ids), ('check_in_at', '>=', low), ('check_in_at', '<', high)],
            order='check_in_at desc')
        has_type = 'visit_type' in self.env['ff.visit']._fields
        onsite = visits.filtered(lambda v: v.visit_type == 'onsite') if has_type else visits
        offsite = visits - onsite
        done = visits.filtered(lambda v: v.state == 'done')
        minutes = sum(done.mapped('duration_min'))
        report.update({
            'tiles': [
                self._tile('Visits', len(visits), '#1a56db', '%d customers' % len(visits.mapped('partner_id'))),
                self._tile('Onsite', len(onsite), '#16a34a',
                           '%d%%' % round(len(onsite) * 100 / len(visits)) if visits else '0%',
                           domain=[('visit_type', '=', 'onsite')] if has_type else []),
                self._tile('Offsite', len(offsite), '#dc2626',
                           '%d%%' % round(len(offsite) * 100 / len(visits)) if visits else '0%',
                           domain=[('visit_type', '=', 'offsite')] if has_type else []),
                self._tile('Productive', len(visits.filtered('productive')), '#7c5cfc',
                           'avg %d min' % (minutes // len(done)) if done else 'avg 0 min',
                           domain=[('productive', '=', True)]),
            ],
            'charts': [
                self._per_day('Visits per day', 'fa-line-chart', start, end, visits,
                              lambda v: self._local_day(v.employee_id, v.check_in_at), lambda v: 1),
                self._bar('Visits by employee', 'fa-user',
                          self._count_by(visits, lambda v: v.employee_id), key='count', money=False),
            ],
            'columns': [
                {'key': 'date', 'label': 'Date'}, {'key': 'employee', 'label': 'Employee', 'bold': True},
                {'key': 'customer', 'label': 'Customer'}, {'key': 'time', 'label': 'In – Out'},
                {'key': 'minutes', 'label': 'Minutes', 'end': True},
                {'key': 'type', 'label': 'Type', 'pill': True}, {'key': 'outcome', 'label': 'Outcome'},
            ],
            'rows': [{
                'id': v.id,
                'date': self._local_day(v.employee_id, v.check_in_at).isoformat(),
                'employee': v.employee_id.name,
                'customer': v.partner_id.display_name,
                'time': '%s – %s' % (v.employee_id._ff_to_local(v.check_in_at).strftime('%H:%M'),
                                     v.employee_id._ff_to_local(v.check_out_at).strftime('%H:%M')
                                     if v.check_out_at else 'now'),
                'minutes': v.duration_min,
                'type': (v.visit_type if has_type else 'onsite'),
                'outcome': v.outcome_id.name or '',
            } for v in visits[:200]],
        })

        # The Visits screen: figures against the period before, a line per type, and who visited most.
        length = (end - start).days + 1
        prev_start, prev_end = start - timedelta(days=length), start - timedelta(days=1)
        before = self.env['ff.visit'].sudo().search([
            ('employee_id', 'in', employees.ids),
            ('check_in_at', '>=', self._ff_day_range(prev_start)[0]),
            ('check_in_at', '<', self._ff_day_range(prev_end)[1])])
        before_onsite = before.filtered(lambda v: v.visit_type == 'onsite') if has_type else before

        def daily(records):
            by_day = {}
            for v in records:
                day = self._local_day(v.employee_id, v.check_in_at)
                by_day[day] = by_day.get(day, 0) + 1
            return by_day

        on_days, off_days, good_days = daily(onsite), daily(offsite), daily(visits.filtered('productive'))
        series = []
        for n in range(length):
            day = start + timedelta(days=n)
            series.append({'label': day.strftime('%d %b'), 'onsite': on_days.get(day, 0),
                           'offsite': off_days.get(day, 0), 'productive': good_days.get(day, 0),
                           'total': on_days.get(day, 0) + off_days.get(day, 0)})
        by_employee = {}
        for v in visits:
            row = by_employee.setdefault(v.employee_id.id, {'id': v.employee_id.id, 'name': v.employee_id.name,
                                                            'count': 0})
            row['count'] += 1
        report['visit'] = {
            'total': len(visits),
            'customers': len(visits.mapped('partner_id')),
            'onsite': len(onsite),
            'offsite': len(offsite),
            'productive': len(visits.filtered('productive')),
            'avg_minutes': (minutes // len(done)) if done else 0,
            'previous': {
                'total': len(before),
                'onsite': len(before_onsite),
                'offsite': len(before - before_onsite),
                'productive': len(before.filtered('productive')),
            },
            'series': series,
            'by_employee': sorted(by_employee.values(), key=lambda row: -row['count']),
        }
        return report

    # ------------------------------------------------------------------
    # Collections
    # ------------------------------------------------------------------
    @api.model
    def ff_collection_report(self, period='month', filters=None):
        if 'ff.collection' not in self.env:
            return None
        employees, start, end, report = self._generic(period, filters, 'ff.collection', 'employee_id', 'date')
        low, high = self._ff_day_range(start)[0], self._ff_day_range(end)[1]
        records = self.env['ff.collection'].sudo().search([
            ('employee_id', 'in', employees.ids), ('date', '>=', low), ('date', '<', high),
            ('state', '!=', 'cancelled')], order='date desc')

        def total(state=None):
            chosen = records.filtered(lambda r: r.state == state) if state else records
            return round(sum(chosen.mapped('amount')), 2), len(chosen)

        amount, count = total()
        held, held_count = total('collected')
        submitted, submitted_count = total('submitted')
        received, received_count = total('received')
        report.update({
            'tiles': [
                self._tile('Collected', amount, '#1a56db', '%d payments' % count, money=True),
                self._tile('With employees', held, '#f59e0b', '%d not deposited' % held_count, money=True,
                           domain=[('state', '=', 'collected')]),
                self._tile('Submitted to office', submitted, '#7c5cfc', '%d payments' % submitted_count, money=True,
                           domain=[('state', '=', 'submitted')]),
                self._tile('Received', received, '#16a34a', '%d payments' % received_count, money=True,
                           domain=[('state', '=', 'received')]),
            ],
            'charts': [
                self._bar('By mode', 'fa-money', self._sum_by(records, lambda r: r.mode_id, lambda r: r.amount)),
                self._bar('By employee', 'fa-user',
                          self._sum_by(records, lambda r: r.employee_id, lambda r: r.amount)),
            ],
            'columns': [
                {'key': 'date', 'label': 'Date'}, {'key': 'employee', 'label': 'Employee', 'bold': True},
                {'key': 'customer', 'label': 'Customer'}, {'key': 'mode', 'label': 'Mode'},
                {'key': 'reference', 'label': 'Reference'},
                {'key': 'amount', 'label': 'Amount', 'money': True, 'end': True},
                {'key': 'state', 'label': 'Status', 'pill': True},
            ],
            'rows': [{
                'id': r.id,
                'date': self._local_day(r.employee_id, r.date).isoformat(),
                'employee': r.employee_id.name,
                'customer': r.partner_id.display_name,
                'mode': r.mode_id.name,
                'reference': r.reference or '',
                'amount': round(r.amount, 2),
                'state': r.state,
            } for r in records[:200]],
        })
        return report

    # ------------------------------------------------------------------
    # Demands
    # ------------------------------------------------------------------
    @api.model
    def ff_demand_section_report(self, period='month', filters=None):
        if 'ff.demand' not in self.env:
            return None
        employees, start, end, report = self._generic(period, filters, 'ff.demand', 'employee_id', 'date')
        low, high = self._ff_day_range(start)[0], self._ff_day_range(end)[1]
        demands = self.env['ff.demand'].sudo().search([
            ('employee_id', 'in', employees.ids), ('date', '>=', low), ('date', '<', high),
            ('state', '!=', 'cancelled')], order='date desc')
        pending = demands.filtered(lambda d: d.state in ('submitted', 'partial'))
        supplied = demands.filtered(lambda d: d.state in ('quoted', 'supplied'))
        total = round(sum(demands.mapped('amount_total')), 2)
        report.update({
            'tiles': [
                self._tile('Demand value', total, '#1a56db', '%d demands' % len(demands), money=True),
                self._tile('Waiting for quotation', round(sum(pending.mapped('amount_total')), 2), '#f59e0b',
                           '%d demands' % len(pending), money=True,
                           domain=[('state', 'in', ['submitted', 'partial'])]),
                self._tile('Quoted / supplied', round(sum(supplied.mapped('amount_total')), 2), '#16a34a',
                           '%d demands' % len(supplied), money=True,
                           domain=[('state', 'in', ['quoted', 'supplied'])]),
                self._tile('Outlets', len(demands.mapped('partner_id')), '#7c5cfc',
                           '%s units' % round(sum(demands.mapped('quantity_total')))),
            ],
            'charts': [
                self._per_day('Demand value per day', 'fa-line-chart', start, end, demands,
                              lambda d: self._local_day(d.employee_id, d.date), lambda d: d.amount_total,
                              money=True),
                self._bar('By distributor', 'fa-truck',
                          self._sum_by(demands, lambda d: d.distributor_id, lambda d: d.amount_total)),
                self._bar('By employee', 'fa-user',
                          self._sum_by(demands, lambda d: d.employee_id, lambda d: d.amount_total)),
            ],
            'columns': [
                {'key': 'name', 'label': 'Number', 'bold': True}, {'key': 'date', 'label': 'Date'},
                {'key': 'employee', 'label': 'Employee'}, {'key': 'customer', 'label': 'Outlet'},
                {'key': 'distributor', 'label': 'Distributor'},
                {'key': 'amount', 'label': 'Value', 'money': True, 'end': True},
                {'key': 'state', 'label': 'Status', 'pill': True},
            ],
            'rows': [{
                'id': d.id,
                'name': d.name,
                'date': self._local_day(d.employee_id, d.date).isoformat(),
                'employee': d.employee_id.name,
                'customer': d.partner_id.display_name,
                'distributor': d.distributor_id.display_name or '',
                'amount': round(d.amount_total, 2),
                'state': d.state,
            } for d in demands[:200]],
        })

        # The Demands screen: four figures against the period before, a daily line, and two top-5 lists.
        length = (end - start).days + 1
        prev_start, prev_end = start - timedelta(days=length), start - timedelta(days=1)
        before = self.env['ff.demand'].sudo().search([
            ('employee_id', 'in', employees.ids), ('state', '!=', 'cancelled'),
            ('date', '>=', self._ff_day_range(prev_start)[0]), ('date', '<', self._ff_day_range(prev_end)[1])])

        def figures(records):
            waiting = records.filtered(lambda d: d.state in ('submitted', 'partial'))
            quoted = records.filtered(lambda d: d.state in ('quoted', 'supplied'))
            return {
                'value': round(sum(records.mapped('amount_total')), 2), 'count': len(records),
                'waiting': round(sum(waiting.mapped('amount_total')), 2), 'waiting_count': len(waiting),
                'quoted': round(sum(quoted.mapped('amount_total')), 2), 'quoted_count': len(quoted),
                'outlets': len(records.mapped('partner_id')), 'units': round(sum(records.mapped('quantity_total'))),
            }

        days = {}
        for d in demands:
            day = self._local_day(d.employee_id, d.date)
            row = days.setdefault(day, {'amount': 0.0, 'count': 0, 'waiting': 0.0, 'quoted': 0.0, 'outlets': set()})
            row['amount'] += d.amount_total
            row['count'] += 1
            row['outlets'].add(d.partner_id.id)
            if d.state in ('submitted', 'partial'):
                row['waiting'] += d.amount_total
            elif d.state in ('quoted', 'supplied'):
                row['quoted'] += d.amount_total
        series = []
        for n in range(length):
            day = start + timedelta(days=n)
            row = days.get(day, {})
            series.append({'label': day.strftime('%d %b'), 'amount': round(row.get('amount', 0.0), 2),
                           'count': row.get('count', 0), 'waiting': round(row.get('waiting', 0.0), 2),
                           'quoted': round(row.get('quoted', 0.0), 2), 'outlets': len(row.get('outlets', ()))})

        def top(key_of):
            rows = {}
            for d in demands:
                key = key_of(d)
                if not key:
                    continue
                row = rows.setdefault(key.id, {'id': key.id, 'name': key.display_name, 'amount': 0.0, 'count': 0})
                row['amount'] += d.amount_total
                row['count'] += 1
            return sorted(({**r, 'amount': round(r['amount'], 2)} for r in rows.values()),
                          key=lambda r: -r['amount'])[:10]

        report['demand'] = {
            **figures(demands),
            'previous': figures(before),
            'series': series,
            'by_distributor': top(lambda d: d.distributor_id),
            'by_employee': top(lambda d: d.employee_id),
        }
        return report

    @api.model
    def ff_target_report(self, period='month', filters=None):
        """Filled in by the Targets module; without it the section says so."""
        return None

    # ------------------------------------------------------------------
    # Excel
    # ------------------------------------------------------------------
    @api.model
    def ff_panel_export(self, section, period='month', filters=None):
        """Write the section's rows to an .xlsx and return a download URL."""
        key = EXPORT_KEYS.get(section)
        Report = self.env['ff.app.report'].sudo()
        employees = self._ff_filtered_employees(filters)
        start, end = self._ff_range(period, filters)
        viewer = self.env.user.employee_id or employees[:1]
        data = Report.ff_run(key, viewer, employees, start, end) if key and viewer else None
        if data is None:
            return False
        who = '%d employees' % len(employees)
        content = Report.ff_xlsx(data, who)
        # No record behind it: readable by the user who exported it (and admins).
        attachment = self.env['ir.attachment'].create({
            'name': '%s_%s_%s.xlsx' % (data['title'].replace(' ', '_'), start.isoformat(), end.isoformat()),
            'datas': base64.b64encode(content),
            'mimetype': 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
            'description': 'ff_panel_export',
        })
        return '/web/content/%d?download=true' % attachment.id

    @api.autovacuum
    def _gc_panel_exports(self):
        """Exports are one-off downloads; keep them a day."""
        self.env['ir.attachment'].sudo().search([
            ('res_model', '=', False), ('description', '=', 'ff_panel_export'),
            ('create_date', '<', fields.Datetime.now() - timedelta(days=1))]).unlink()
