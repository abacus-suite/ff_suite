"""Panel sections for tasks, samples and outlets, the extra demand figures, and their Excel."""
import base64
import io

from odoo import api, models

TASK_COLORS = {
    'client_visit': '#1a56db', 'new_lead': '#16a34a', 'lead_follow_up': '#f59e0b',
    'adhoc': '#64748b', 'sample_collection': '#7c5cfc', 'marketing_supply': '#0ea5a5',
}


class FfDashboardTasks(models.AbstractModel):
    _inherit = 'ff.dashboard'

    # ------------------------------------------------------------------
    # Tasks
    # ------------------------------------------------------------------
    @api.model
    def ff_task_section_report(self, period='month', filters=None):
        if 'ff.task.log' not in self.env:
            return None
        employees, start, end, report = self._generic(period, filters, 'ff.task.log', 'employee_id', 'date')
        low, high = self._ff_day_range(start)[0], self._ff_day_range(end)[1]
        logs = self.env['ff.task.log'].sudo().search([
            ('employee_id', 'in', employees.ids), ('date', '>=', low), ('date', '<', high)], order='date desc')
        types = self.env['ff.task.type'].sudo().with_context(active_test=False).search([])
        contacts = logs.mapped('partner_id') - self.env.company.partner_id
        tiles = [self._tile('Tasks', len(logs), '#1a56db', '%d employees' % len(logs.mapped('employee_id')))]
        for task_type in types:
            count = len(logs.filtered(lambda l, t=task_type: l.task_type_id == t))
            tiles.append(self._tile(task_type.name, count, TASK_COLORS.get(task_type.code, '#1a56db'),
                                    domain=[('task_code', '=', task_type.code)]))
        tiles.append(self._tile('Contacts met', len(contacts), '#dc2626'))
        by_type = [{'name': t.name, 'count': len(logs.filtered(lambda l, t=t: l.task_type_id == t))} for t in types]
        outcome_labels = {}
        for field in ('visit_outcome', 'meeting_result', 'lead_outcome'):
            outcome_labels[field] = dict(self.env['ff.task.log']._fields[field]._description_selection(self.env))

        def result(log):
            return (outcome_labels['visit_outcome'].get(log.visit_outcome)
                    or outcome_labels['meeting_result'].get(log.meeting_result)
                    or outcome_labels['lead_outcome'].get(log.lead_outcome) or '')

        report.update({
            'tiles': tiles,
            'charts': [
                self._per_day('Tasks per day', 'fa-line-chart', start, end, logs,
                              lambda l: self._local_day(l.employee_id, l.date), lambda l: 1),
                self._bar('Tasks by type', 'fa-tasks', [r for r in by_type if r['count']], key='count', money=False),
                self._bar('Tasks by employee', 'fa-user',
                          self._count_by(logs, lambda l: l.employee_id), key='count', money=False),
            ],
            'columns': [
                {'key': 'date', 'label': 'Date'}, {'key': 'employee', 'label': 'Employee', 'bold': True},
                {'key': 'task', 'label': 'Task', 'pill': True}, {'key': 'customer', 'label': 'Contact'},
                {'key': 'type', 'label': 'Type', 'pill': True},
                {'key': 'result', 'label': 'Result'}, {'key': 'name', 'label': 'Number'},
            ],
            'rows': [{
                'id': l.id,
                'date': self._local_day(l.employee_id, l.date).isoformat(),
                'employee': l.employee_id.name,
                'task': l.task_type_id.name,
                'customer': l.partner_id.display_name or '',
                'type': 'Onsite' if (l.visit_id and l.visit_id.visit_type == 'onsite') else 'Offsite',
                'result': result(l),
                'name': l.name,
            } for l in logs[:200]],
        })
        return report

    # ------------------------------------------------------------------
    # Samples
    # ------------------------------------------------------------------
    @api.model
    def ff_sample_section_report(self, period='month', filters=None):
        if 'ff.sample.move' not in self.env:
            return None
        employees, start, end, report = self._generic(period, filters, 'ff.sample.move', 'employee_id', 'date')
        Move = self.env['ff.sample.move'].sudo()
        low, high = self._ff_day_range(start)[0], self._ff_day_range(end)[1]
        moves = Move.search([('employee_id', 'in', employees.ids), ('date', '>=', low), ('date', '<', high)],
                            order='date desc')
        taken = sum(moves.mapped('qty_in'))
        given = sum(moves.mapped('qty_out'))
        held = Move.search([('employee_id', 'in', employees.ids)])
        by_person = {}
        by_product = {}
        for move in held:
            by_person[move.employee_id] = by_person.get(move.employee_id, 0.0) + move.balance
            by_product[move.product_id] = by_product.get(move.product_id, 0.0) + move.balance
        in_hand = sum(by_person.values())
        report.update({
            'tiles': [
                self._tile('Taken', round(taken, 2), '#1a56db', '%d movements' % len(moves.filtered('qty_in')),
                           domain=[('direction', '=', 'in')]),
                self._tile('Given', round(given, 2), '#7c5cfc', '%d movements' % len(moves.filtered('qty_out')),
                           domain=[('direction', '=', 'out')]),
                self._tile('In hand now', round(in_hand, 2), '#16a34a',
                           '%d people holding' % len([v for v in by_person.values() if v > 0])),
                self._tile('Given to leads', round(sum(moves.filtered(lambda m: m.partner_type == 'lead').mapped('qty_out')), 2),
                           '#f59e0b', domain=[('partner_type', '=', 'lead')]),
            ],
            'charts': [
                self._per_day('Samples taken per day', 'fa-line-chart', start, end, moves,
                              lambda m: self._local_day(m.employee_id, m.date), lambda m: m.qty_in),
                self._per_day('Samples given per day', 'fa-line-chart', start, end, moves,
                              lambda m: self._local_day(m.employee_id, m.date), lambda m: m.qty_out),
                self._bar('In hand by employee', 'fa-user',
                          sorted(({'name': e.name, 'amount': round(v, 2)} for e, v in by_person.items() if v),
                                 key=lambda r: -r['amount'])[:10], money=False),
                self._bar('In hand by flavour', 'fa-flask',
                          sorted(({'name': p.display_name, 'amount': round(v, 2)} for p, v in by_product.items() if v),
                                 key=lambda r: -r['amount'])[:10], money=False),
            ],
            'columns': [
                {'key': 'date', 'label': 'Date'}, {'key': 'employee', 'label': 'Employee', 'bold': True},
                {'key': 'product', 'label': 'Flavour'}, {'key': 'direction', 'label': 'Direction', 'pill': True},
                {'key': 'qty', 'label': 'Qty', 'end': True}, {'key': 'source', 'label': 'Taken from'},
                {'key': 'contact', 'label': 'Contact'},
            ],
            'rows': [{
                'id': m.id,
                'date': self._local_day(m.employee_id, m.date).isoformat(),
                'employee': m.employee_id.name,
                'product': m.product_id.display_name,
                'direction': 'Taken' if m.direction == 'in' else 'Given',
                'qty': m.quantity,
                'source': dict(m._fields['source_type'].selection).get(m.source_type, '') if m.source_type else '',
                'contact': m.partner_id.display_name or '',
            } for m in moves[:200]],
        })
        return report

    # ------------------------------------------------------------------
    # Outlets and what they owe
    # ------------------------------------------------------------------
    @api.model
    def ff_outlet_section_report(self, period='month', filters=None):
        if 'ff.outlet.invoice' not in self.env:
            return None
        employees, start, end, report = self._generic(period, filters, 'ff.outlet.invoice', 'employee_id', 'date')
        Partner = self.env['res.partner'].sudo()
        Invoice = self.env['ff.outlet.invoice'].sudo()
        invoices = Invoice.search([('employee_id', 'in', employees.ids), ('date', '>=', start), ('date', '<=', end),
                                   ('state', '!=', 'cancelled')], order='date desc')
        open_invoices = Invoice.search([('employee_id', 'in', employees.ids), ('state', 'in', ('open', 'partial'))])
        overdue = open_invoices.filtered('overdue')
        tiles = [
            self._tile('Invoiced', round(sum(invoices.mapped('amount_total')), 2), '#1a56db',
                       '%d invoices' % len(invoices), money=True),
            self._tile('Collected', round(sum(invoices.mapped('amount_collected')), 2), '#16a34a', money=True),
            self._tile('Pending', round(sum(open_invoices.mapped('amount_pending')), 2), '#f59e0b',
                       '%d open invoices' % len(open_invoices), money=True,
                       domain=[('state', 'in', ['open', 'partial'])]),
            self._tile('Overdue', round(sum(overdue.mapped('amount_pending')), 2), '#dc2626',
                       '%d invoices' % len(overdue), money=True),
        ]
        status_rows = []
        has_status = 'ff_status' in Partner._fields
        if has_status:
            domain = [('ff_is_client', '=', True), ('ff_employee_ids', 'in', employees.ids)]
            labels = dict(Partner._fields['ff_status'].selection)
            for code in ('new_lead', 'onboard_pending', 'onboarded', 'stopped', 'not_interested'):
                status_rows.append({'name': labels[code], 'count': Partner.search_count(domain + [('ff_status', '=', code)])})
            joined = Partner.search_count(domain + [('ff_onboarded_date', '>=', start), ('ff_onboarded_date', '<=', end)])
            tiles += [
                self._tile('New leads', status_rows[0]['count'], '#7c5cfc'),
                self._tile('Pending onboarding', status_rows[1]['count'], '#f59e0b'),
                self._tile('Onboarded in period', joined, '#16a34a', '%d onboarded in all' % status_rows[2]['count']),
                self._tile('Not interested', status_rows[4]['count'], '#64748b'),
            ]
        by_distributor = {}
        for invoice in open_invoices:
            by_distributor[invoice.distributor_id] = by_distributor.get(invoice.distributor_id, 0.0) + invoice.amount_pending
        report.update({
            'tiles': tiles,
            'charts': [
                self._per_day('Invoiced per day', 'fa-line-chart', start, end, invoices,
                              lambda i: i.date, lambda i: i.amount_total, money=True),
                self._bar('Pending by distributor', 'fa-truck',
                          sorted(({'name': d.display_name, 'amount': round(v, 2)} for d, v in by_distributor.items()),
                                 key=lambda r: -r['amount'])[:10]),
            ] + ([self._bar('Contacts by status', 'fa-building-o', status_rows, key='count', money=False)]
                 if status_rows else []),
            'columns': [
                {'key': 'name', 'label': 'Invoice', 'bold': True}, {'key': 'date', 'label': 'Date'},
                {'key': 'due', 'label': 'Due'}, {'key': 'customer', 'label': 'Outlet'},
                {'key': 'distributor', 'label': 'Distributor'},
                {'key': 'amount', 'label': 'Amount', 'money': True, 'end': True},
                {'key': 'collected', 'label': 'Collected', 'money': True, 'end': True},
                {'key': 'pending', 'label': 'Pending', 'money': True, 'end': True},
                {'key': 'state', 'label': 'Status', 'pill': True},
            ],
            'rows': [{
                'id': i.id, 'name': i.name, 'date': i.date.isoformat(),
                'due': i.due_date.isoformat() if i.due_date else '',
                'customer': i.partner_id.display_name, 'distributor': i.distributor_id.display_name,
                'amount': round(i.amount_total, 2), 'collected': round(i.amount_collected, 2),
                'pending': round(i.amount_pending, 2), 'state': i.state,
            } for i in invoices[:200]],
        })
        return report

    # ------------------------------------------------------------------
    # Demands: which have a distributor, free goods, taxes
    # ------------------------------------------------------------------
    @api.model
    def ff_demand_section_report(self, period='month', filters=None):
        report = super().ff_demand_section_report(period, filters)
        if not report or not report.get('demand') or 'ff.demand' not in self.env:
            return report
        employees = self._ff_filtered_employees(filters)
        start, end = self._ff_range(period, filters)
        low, high = self._ff_day_range(start)[0], self._ff_day_range(end)[1]
        demands = self.env['ff.demand'].sudo().search([
            ('employee_id', 'in', employees.ids), ('date', '>=', low), ('date', '<', high),
            ('state', '!=', 'cancelled')])
        linked = demands.filtered('distributor_id')
        fields_ = self.env['ff.demand']._fields
        extra = [
            {'label': 'Linked to a distributor', 'value': len(linked), 'color': '#16a34a',
             'sub': '%d%% of demands' % (round(len(linked) * 100 / len(demands)) if demands else 0)},
            {'label': 'No distributor yet', 'value': len(demands - linked), 'color': '#f59e0b',
             'sub': 'to link when sending'},
        ]
        if 'foc_value' in fields_:
            extra.append({'label': 'Free goods given', 'value': round(sum(demands.mapped('foc_value')), 2),
                          'color': '#7c5cfc', 'money': True, 'sub': 'worth, at PTR'})
        if 'amount_tax' in fields_:
            extra.append({'label': 'Taxes', 'value': round(sum(demands.mapped('amount_tax')), 2),
                          'color': '#0ea5a5', 'money': True})
        report['demand']['extra'] = extra
        return report

    # ------------------------------------------------------------------
    # Excel for the new sections
    # ------------------------------------------------------------------
    @api.model
    def ff_panel_export(self, section, period='month', filters=None):
        if section == 'tasks':
            employees = self._ff_filtered_employees(filters)
            start, end = self._ff_range(period, filters)
            return self.env['ff.task.summary'].ff_download(employees.sorted('name'), start, end)
        if section in ('samples', 'outlets'):
            method = {'samples': 'ff_sample_section_report', 'outlets': 'ff_outlet_section_report'}[section]
            report = getattr(self, method)(period, filters)
            if not report:
                return False
            return self._ff_rows_xlsx(section.title(), report)
        return super().ff_panel_export(section, period, filters)

    @api.model
    def _ff_rows_xlsx(self, title, report):
        import xlsxwriter

        buffer = io.BytesIO()
        book = xlsxwriter.Workbook(buffer, {'in_memory': True})
        sheet = book.add_worksheet(title[:31])
        head = book.add_format({'bold': True, 'bg_color': '#DCE7FB', 'border': 1})
        cell = book.add_format({'border': 1})
        money = book.add_format({'border': 1, 'num_format': '#,##0.00'})
        sheet.write(0, 0, title, book.add_format({'bold': True, 'font_size': 14}))
        sheet.write(1, 0, report.get('period_label') or '')
        columns = report['columns']
        for index, column in enumerate(columns):
            sheet.write(3, index, column['label'], head)
            sheet.set_column(index, index, 22 if not column.get('end') else 14)
        for n, row in enumerate(report['rows'], 4):
            for index, column in enumerate(columns):
                value = row.get(column['key'], '')
                if isinstance(value, (int, float)):
                    sheet.write_number(n, index, value, money if column.get('money') else cell)
                else:
                    sheet.write(n, index, value, cell)
        sheet.freeze_panes(4, 0)
        book.close()
        attachment = self.env['ir.attachment'].create({
            'name': '%s_%s.xlsx' % (title, report.get('period_label') or ''),
            'datas': base64.b64encode(buffer.getvalue()), 'description': 'ff_panel_export',
            'mimetype': 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
        })
        return '/web/content/%d?download=true' % attachment.id
