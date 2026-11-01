"""The daily task summary: what each person did, day by day, as an Excel file.

One tab per employee when several are chosen, with a tab for everybody first;
one tab when it is a single person. Each employee tab has the day-by-day
summary on top and every task listed below it.
"""
import base64
import io
import re
from datetime import datetime, timedelta

from odoo import api, fields, models

PERIODS = [
    ('today', 'Today'),
    ('yesterday', 'Yesterday'),
    ('this_week', 'This Week'),
    ('last_week', 'Last Week'),
    ('this_month', 'This Month'),
    ('last_month', 'Last Month'),
    ('custom', 'Choose Dates'),
]


def period_dates(today, period):
    """The first and last day of a named period."""
    if period == 'yesterday':
        day = today - timedelta(days=1)
        return day, day
    if period == 'this_week':
        monday = today - timedelta(days=today.weekday())
        return monday, monday + timedelta(days=6)
    if period == 'last_week':
        monday = today - timedelta(days=today.weekday() + 7)
        return monday, monday + timedelta(days=6)
    if period == 'this_month':
        first = today.replace(day=1)
        return first, (first + timedelta(days=32)).replace(day=1) - timedelta(days=1)
    if period == 'last_month':
        last = today.replace(day=1) - timedelta(days=1)
        return last.replace(day=1), last
    return today, today


class FfTaskSummary(models.AbstractModel):
    _name = 'ff.task.summary'
    _description = 'Daily Task Summary'

    # ------------------------------------------------------------------
    # The numbers
    # ------------------------------------------------------------------
    @api.model
    def _ff_task_types(self):
        return self.env['ff.task.type'].sudo().with_context(active_test=False).search([])

    @api.model
    def ff_collect(self, employee, start, end):
        """Day rows and task rows for one employee between two local dates."""
        employee = employee.sudo()
        env = self.env
        low = employee._ff_day_bounds(start)[0]
        high = employee._ff_day_bounds(end)[1]

        def local_day(value):
            return employee._ff_to_local(value).date() if value else None

        types = self._ff_task_types()
        logs = env['ff.task.log'].sudo().search([
            ('employee_id', '=', employee.id), ('date', '>=', low), ('date', '<', high)], order='date asc')
        attendance = env['hr.attendance'].sudo().search([
            ('employee_id', '=', employee.id), ('check_in', '>=', low), ('check_in', '<', high)], order='check_in asc')
        moves = env['ff.sample.move'].sudo().search([
            ('employee_id', '=', employee.id), ('date', '>=', low), ('date', '<', high)])
        demands = env['ff.demand'].sudo().search([
            ('employee_id', '=', employee.id), ('date', '>=', low), ('date', '<', high),
            ('state', '!=', 'cancelled')]) if 'ff.demand' in env else env['hr.employee']
        collections = env['ff.collection'].sudo().search([
            ('employee_id', '=', employee.id), ('date', '>=', low), ('date', '<', high)]) \
            if 'ff.collection' in env else env['hr.employee']
        visits = env['ff.visit'].sudo().search([
            ('employee_id', '=', employee.id), ('check_in_at', '>=', low), ('check_in_at', '<', high)])

        outcome_labels = {}
        for field in ('visit_outcome', 'meeting_result', 'lead_outcome'):
            outcome_labels[field] = dict(env['ff.task.log']._fields[field]._description_selection(env))

        days = []
        for number in range((end - start).days + 1):
            day = start + timedelta(days=number)
            todays = logs.filtered(lambda l, d=day: local_day(l.date) == d)
            attended = attendance.filtered(lambda a, d=day: local_day(a.check_in) == d)
            outs = [a.check_out for a in attended if a.check_out]
            contacts = todays.mapped('partner_id') - employee.company_id.partner_id
            row = {
                'date': day,
                'weekday': day.strftime('%a'),
                'first_in': employee._ff_to_local(attended[0].check_in).strftime('%H:%M') if attended else '',
                'last_out': employee._ff_to_local(max(outs)).strftime('%H:%M') if outs and len(outs) == len(attended) else '',
                'worked': round(sum(attended.mapped('worked_hours')), 2),
                'tasks': len(todays),
                'by_type': {t.code: len(todays.filtered(lambda l, t=t: l.task_type_id == t)) for t in types},
                'contacts': len(contacts),
                'visits': len(visits.filtered(lambda v, d=day: local_day(v.check_in_at) == d)),
                'samples_in': sum(moves.filtered(lambda m, d=day: local_day(m.date) == d).mapped('qty_in')),
                'samples_out': sum(moves.filtered(lambda m, d=day: local_day(m.date) == d).mapped('qty_out')),
                'demands': len(demands.filtered(lambda r, d=day: local_day(r.date) == d)),
                'demand_value': round(sum(demands.filtered(lambda r, d=day: local_day(r.date) == d).mapped('amount_total')), 2),
                'collected': round(sum(collections.filtered(lambda r, d=day: local_day(r.date) == d).mapped('amount')), 2),
            }
            days.append(row)

        tasks = []
        for log in logs:
            stamp = employee._ff_to_local(log.date)
            result = (outcome_labels['visit_outcome'].get(log.visit_outcome)
                      or outcome_labels['meeting_result'].get(log.meeting_result)
                      or outcome_labels['lead_outcome'].get(log.lead_outcome) or '')
            quantity = sum(log.line_ids.filtered(lambda l: l.kind == 'sample').mapped('quantity'))
            tasks.append({
                'date': stamp.date(), 'time': stamp.strftime('%H:%M'), 'number': log.name,
                'task': log.task_type_id.name, 'contact': log.partner_id.display_name or '',
                'type': dict(log.partner_id._fields['ff_category_type']._description_selection(env)).get(
                    log.partner_id.ff_category_type, '') if log.partner_id else '',
                'visit_type': 'Onsite' if (log.visit_id and log.visit_id.visit_type == 'onsite') else 'Offsite',
                'result': result, 'samples': quantity,
                'demands': ', '.join(log.demand_ids.mapped('name')),
                'note': (log.outcome_note or log.description or log.meeting_update or ''),
            })
        return {'employee': employee, 'types': types, 'days': days, 'tasks': tasks}

    # ------------------------------------------------------------------
    # The workbook
    # ------------------------------------------------------------------
    @api.model
    def ff_xlsx(self, employees, start, end):
        """One .xlsx: a tab for everybody (when several), then one tab per employee."""
        import xlsxwriter

        buffer = io.BytesIO()
        book = xlsxwriter.Workbook(buffer, {'in_memory': True})
        fmt = {
            'title': book.add_format({'bold': True, 'font_size': 15, 'font_color': '#1B3A7A'}),
            'sub': book.add_format({'font_color': '#5B6B8C'}),
            'head': book.add_format({'bold': True, 'bg_color': '#DCE7FB', 'border': 1, 'text_wrap': True,
                                     'valign': 'vcenter', 'align': 'center'}),
            'cell': book.add_format({'border': 1}),
            'num': book.add_format({'border': 1, 'num_format': '#,##0.##'}),
            'money': book.add_format({'border': 1, 'num_format': '#,##0.00'}),
            'date': book.add_format({'border': 1, 'num_format': 'dd-mmm-yyyy'}),
            'total': book.add_format({'bold': True, 'bg_color': '#F1F5FF', 'border': 1, 'num_format': '#,##0.##'}),
            'totalm': book.add_format({'bold': True, 'bg_color': '#F1F5FF', 'border': 1, 'num_format': '#,##0.00'}),
            'totalt': book.add_format({'bold': True, 'bg_color': '#F1F5FF', 'border': 1}),
            'zero': book.add_format({'border': 1, 'font_color': '#B8C0CC', 'num_format': '#,##0.##'}),
        }
        period = '%s to %s' % (start.strftime('%d-%b-%Y'), end.strftime('%d-%b-%Y'))
        payload = [self.ff_collect(employee, start, end) for employee in employees]
        used = set()

        def sheet_name(text):
            base = re.sub(r'[\[\]:*?/\\]', ' ', text or 'Employee').strip()[:28] or 'Employee'
            base = re.sub(r'\s+', ' ', base).strip() or 'Employee'
            name, n = base, 1
            while name.lower() in used:
                n += 1
                name = '%s %d' % (base[:26], n)
            used.add(name.lower())
            return name

        def table_columns(types):
            columns = [('Date', 'date', 13), ('Day', 'weekday', 6), ('First check-in', 'first_in', 12),
                       ('Last check-out', 'last_out', 12), ('Hours worked', 'worked', 10),
                       ('Total tasks', 'tasks', 9)]
            columns += [(t.name, 'type:%s' % t.code, 12) for t in types]
            columns += [('Contacts met', 'contacts', 10), ('Visits', 'visits', 8),
                        ('Samples taken', 'samples_in', 10), ('Samples given', 'samples_out', 10),
                        ('Demands', 'demands', 9), ('Demand value', 'demand_value', 13),
                        ('Collected', 'collected', 12)]
            return columns

        def value_of(row, key):
            if key.startswith('type:'):
                return row['by_type'].get(key[5:], 0)
            return row.get(key, '')

        def draw_days(sheet, top, data):
            columns = table_columns(data['types'])
            for index, (label, _key, width) in enumerate(columns):
                sheet.write(top, index, label, fmt['head'])
                sheet.set_column(index, index, width)
            sheet.set_row(top, 32)
            totals = {}
            for n, row in enumerate(data['days'], 1):
                for index, (_label, key, _w) in enumerate(columns):
                    value = value_of(row, key)
                    if key == 'date':
                        sheet.write_datetime(top + n, index, datetime.combine(value, datetime.min.time()), fmt['date'])
                    elif isinstance(value, (int, float)):
                        style = fmt['money'] if key in ('demand_value', 'collected') else (fmt['zero'] if not value else fmt['num'])
                        sheet.write_number(top + n, index, value, style)
                        totals[key] = totals.get(key, 0) + value
                    else:
                        sheet.write(top + n, index, value, fmt['cell'])
            last = top + len(data['days']) + 1
            sheet.write(last, 0, 'Total', fmt['totalt'])
            for index, (_label, key, _w) in enumerate(columns[1:], 1):
                if key in totals:
                    sheet.write_number(last, index, round(totals[key], 2),
                                      fmt['totalm'] if key in ('demand_value', 'collected') else fmt['total'])
                else:
                    sheet.write(last, index, '', fmt['totalt'])
            return last, totals

        def draw_tasks(sheet, top, data):
            heads = [('Date', 13), ('Time', 8), ('Task no.', 16), ('Task', 24), ('Contact', 30), ('Contact type', 14),
                     ('Type', 12), ('Result', 22), ('Samples', 9), ('Demands', 22), ('Note', 45)]
            sheet.write(top, 0, 'Task details', fmt['title'])
            for index, (label, _w) in enumerate(heads):
                sheet.write(top + 1, index, label, fmt['head'])
            for n, task in enumerate(data['tasks'], 2):
                sheet.write_datetime(top + n, 0, datetime.combine(task['date'], datetime.min.time()), fmt['date'])
                for index, key in enumerate(('time', 'number', 'task', 'contact', 'type', 'visit_type', 'result'), 1):
                    sheet.write(top + n, index, task[key], fmt['cell'])
                sheet.write_number(top + n, 8, task['samples'], fmt['num'])
                sheet.write(top + n, 9, task['demands'], fmt['cell'])
                sheet.write(top + n, 10, task['note'], fmt['cell'])
            if not data['tasks']:
                sheet.write(top + 2, 0, 'No tasks in this period.', fmt['sub'])

        # ---- everybody first, when there is more than one
        if len(payload) > 1:
            sheet = book.add_worksheet(sheet_name('All Employees'))
            sheet.write(0, 0, 'Daily Task Summary: All Employees', fmt['title'])
            sheet.write(1, 0, period, fmt['sub'])
            types = payload[0]['types']
            heads = ['Employee', 'Team', 'Days worked', 'Total tasks'] + [t.name for t in types] + [
                'Contacts met', 'Samples taken', 'Samples given', 'Demands', 'Demand value', 'Collected']
            for index, label in enumerate(heads):
                sheet.write(3, index, label, fmt['head'])
                sheet.set_column(index, index, 26 if index == 0 else 13)
            sheet.set_row(3, 32)
            grand = [0] * (len(heads) - 2)
            for n, data in enumerate(payload, 4):
                days = data['days']
                values = [
                    sum(1 for d in days if d['first_in']), sum(d['tasks'] for d in days),
                    *[sum(d['by_type'].get(t.code, 0) for d in days) for t in types],
                    sum(d['contacts'] for d in days), sum(d['samples_in'] for d in days),
                    sum(d['samples_out'] for d in days), sum(d['demands'] for d in days),
                    round(sum(d['demand_value'] for d in days), 2), round(sum(d['collected'] for d in days), 2)]
                sheet.write(n, 0, data['employee'].name, fmt['cell'])
                sheet.write(n, 1, data['employee'].ff_team_id.name or '', fmt['cell'])
                for index, value in enumerate(values, 2):
                    sheet.write_number(n, index, value, fmt['money'] if index >= len(heads) - 2 else fmt['num'])
                grand = [g + v for g, v in zip(grand, values)]
            total_row = 4 + len(payload)
            sheet.write(total_row, 0, 'Total', fmt['totalt'])
            sheet.write(total_row, 1, '', fmt['totalt'])
            for index, value in enumerate(grand, 2):
                sheet.write_number(total_row, index, round(value, 2),
                                   fmt['totalm'] if index >= len(heads) - 2 else fmt['total'])
            sheet.freeze_panes(4, 1)

        # ---- one tab per person
        for data in payload:
            employee = data['employee']
            sheet = book.add_worksheet(sheet_name(employee.name))
            sheet.write(0, 0, 'Daily Task Summary: %s' % employee.name, fmt['title'])
            sheet.write(1, 0, '%s%s' % (period, '   |   Team: %s' % employee.ff_team_id.name if employee.ff_team_id else ''),
                        fmt['sub'])
            last, _totals = draw_days(sheet, 3, data)
            draw_tasks(sheet, last + 3, data)
            sheet.freeze_panes(4, 1)
        if not payload:
            book.add_worksheet('Summary').write(0, 0, 'No employees were chosen.')
        book.close()
        return buffer.getvalue()

    @api.model
    def ff_download(self, employees, start, end):
        """The workbook as an attachment, and the URL that downloads it."""
        content = self.ff_xlsx(employees, start, end)
        name = 'Daily_Task_Summary_%s_%s%s.xlsx' % (
            start.isoformat(), end.isoformat(), '_%s' % re.sub(r'\W+', '_', employees.name) if len(employees) == 1 else '')
        attachment = self.env['ir.attachment'].create({
            'name': name, 'datas': base64.b64encode(content), 'description': 'ff_panel_export',
            'mimetype': 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
        })
        return '/web/content/%d?download=true' % attachment.id


class FfTaskSummaryWizard(models.TransientModel):
    _name = 'ff.task.summary.wizard'
    _description = 'Daily Task Summary (Excel)'

    period = fields.Selection(PERIODS, default='this_month', required=True)
    date_from = fields.Date(required=True, default=lambda self: period_dates(fields.Date.context_today(self), 'this_month')[0])
    date_to = fields.Date(required=True, default=lambda self: period_dates(fields.Date.context_today(self), 'this_month')[1])
    who = fields.Selection([('all', 'All employees'), ('selected', 'Chosen employees')], default='all', required=True,
                           string='Employees')
    employee_ids = fields.Many2many('hr.employee', string='Choose Employees')
    team_id = fields.Many2one('ff.team', string='Only This Team')

    @api.onchange('period')
    def _onchange_period(self):
        if self.period and self.period != 'custom':
            self.date_from, self.date_to = period_dates(fields.Date.context_today(self), self.period)

    @api.model
    def _ff_scope(self):
        Employee = self.env['hr.employee'].sudo()
        if self.env.user.has_group('ff_base.group_ff_admin'):
            return Employee.search([('company_id', 'in', self.env.companies.ids)])
        return Employee.browse(self.env.user.ff_scope_employee_ids()).exists()

    def action_download(self):
        self.ensure_one()
        if self.date_to < self.date_from:
            self.date_from, self.date_to = self.date_to, self.date_from
        scope = self._ff_scope()
        employees = self.employee_ids & scope if self.who == 'selected' else scope
        if self.team_id:
            employees = employees.filtered(lambda e: e.ff_team_id == self.team_id)
        url = self.env['ff.task.summary'].ff_download(employees.sorted('name'), self.date_from, self.date_to)
        return {'type': 'ir.actions.act_url', 'url': url, 'target': 'self'}
