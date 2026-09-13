"""Report catalogue for the mobile app.

Each report is a column list plus a row builder over a set of employees and a
local date range. The app draws the same payload as a list or a table, and the
Excel export writes it unchanged - one definition, three views.
"""
from datetime import datetime, time, timedelta

from odoo import api, models

# Column types the app knows how to format.
TEXT, DATE, TIME, NUMBER, MONEY, HOURS, KM, STATUS = (
    'text', 'date', 'time', 'number', 'money', 'hours', 'km', 'status')


def col(key, label, kind=TEXT, total=False):
    return {'key': key, 'label': label, 'type': kind, 'total': total}


class FfAppReport(models.AbstractModel):
    _name = 'ff.app.report'
    _description = 'Field Force App Reports'

    # ------------------------------------------------------------------
    # Catalogue
    # ------------------------------------------------------------------
    def _definitions(self):
        """key -> (title, description, icon, needed model, columns, builder)."""
        demand = self._order_flow() == 'demand' and 'ff.demand' in self.env
        if demand:
            orders = ('Demands', 'Demands taken from outlets', 'shopping_basket', 'ff.demand', [
                col('date', 'Date', DATE), col('employee', 'Employee'), col('number', 'Number'),
                col('customer', 'Outlet'), col('distributor', 'Distributor'), col('units', 'Units', NUMBER, True),
                col('amount', 'Value', MONEY, True), col('status', 'Status', STATUS)], self._demands)
        else:
            orders = ('Orders', 'Sale orders taken in the app', 'shopping_cart', 'sale.order', [
                col('date', 'Date', DATE), col('employee', 'Employee'), col('number', 'Number'),
                col('customer', 'Customer'), col('amount', 'Amount', MONEY, True),
                col('status', 'Status', STATUS)], self._orders)
        defs = {
            'attendance': ('Attendance', 'Punch in / out and hours worked per day', 'fingerprint', 'hr.attendance', [
                col('date', 'Date', DATE), col('employee', 'Employee'), col('check_in', 'In', TIME),
                col('check_out', 'Out', TIME), col('hours', 'Hours', HOURS, True), col('km', 'Distance', KM, True),
                col('status', 'Status', STATUS)], self._attendance),
            'visits': ('Customer visits', 'Every check-in, onsite or offsite', 'storefront', 'ff.visit', [
                col('date', 'Date', DATE), col('employee', 'Employee'), col('customer', 'Customer'),
                col('check_in', 'In', TIME), col('check_out', 'Out', TIME), col('minutes', 'Minutes', NUMBER, True),
                col('visit_type', 'Type', STATUS), col('distance', 'Away (m)', NUMBER),
                col('outcome', 'Outcome')], self._visits),
            'orders': orders,
            'collections': ('Payment collections', 'Cash, online, cheque and PDC collected', 'payments',
                            'ff.collection', [
                col('date', 'Date', DATE), col('employee', 'Employee'), col('customer', 'Customer'),
                col('mode', 'Mode'), col('reference', 'Reference'), col('amount', 'Amount', MONEY, True),
                col('status', 'Status', STATUS)], self._collections),
            'expenses': ('Expenses', 'Expense claims and their approval', 'receipt', 'ff.expense.claim', [
                col('date', 'Date', DATE), col('reference', 'Reference'), col('employee', 'Employee'),
                col('category', 'Type'), col('amount', 'Amount', MONEY, True), col('status', 'Status', STATUS)],
                self._expenses),
            'allowances': ('Travel allowance', 'Daily distance allowance claims', 'local_gas_station',
                           'ff.allowance.claim', [
                col('date', 'Date', DATE), col('reference', 'Reference'), col('employee', 'Employee'),
                col('km', 'Distance', KM, True), col('visits', 'Visits', NUMBER, True),
                col('amount', 'Amount', MONEY, True), col('status', 'Status', STATUS)], self._allowances),
            'leaves': ('Time off', 'Leave requests in the period', 'beach_access', 'hr.leave', [
                col('employee', 'Employee'), col('type', 'Leave type'), col('date', 'From', DATE),
                col('date_to', 'To', DATE), col('days', 'Days', NUMBER, True), col('status', 'Status', STATUS)],
                self._leaves),
            'distance': ('Distance travelled', 'GPS kilometres per day', 'route', 'ff.daily.track', [
                col('date', 'Date', DATE), col('employee', 'Employee'), col('km', 'Distance', KM, True),
                col('first', 'First ping', TIME), col('last', 'Last ping', TIME),
                col('pings', 'Pings', NUMBER, True)], self._distance),
            'customers': ('Customers added', 'New customers created from the app', 'add_business', 'res.partner', [
                col('date', 'Date', DATE), col('employee', 'Employee'), col('customer', 'Customer'),
                col('category', 'Category'), col('city', 'City'), col('phone', 'Phone'),
                col('status', 'Approval', STATUS)], self._customers),
        }
        return {key: value for key, value in defs.items() if value[3] in self.env}

    @api.model
    def ff_catalogue(self):
        return [{'key': key, 'title': d[0], 'description': d[1], 'icon': d[2]}
                for key, d in self._definitions().items()]

    @api.model
    def ff_run(self, key, viewer, employees, start, end):
        """Rows of report ``key`` for ``employees``, local dates ``start``..``end`` inclusive.

        ``viewer`` is the app user; their timezone decides where a day begins.
        """
        # The viewer goes into the context before the builders are bound:
        # each one reads it to know where the viewer's day starts and ends.
        report = self.with_context(ff_report_viewer=viewer.id)
        definition = report._definitions().get(key)
        if not definition:
            return None
        title, _description, _icon, _model, columns, builder = definition
        if end < start:
            start, end = end, start
        rows = builder(employees.sudo(), start, end) if employees else []
        totals = {column['key']: round(sum(row.get(column['key']) or 0 for row in rows), 2)
                  for column in columns if column['total']}
        return {
            'key': key,
            'title': title,
            'start': start.isoformat(),
            'end': end.isoformat(),
            'currency': viewer.company_id.currency_id.name,
            'columns': columns,
            'rows': rows,
            'totals': totals,
        }

    # ------------------------------------------------------------------
    # Helpers
    # ------------------------------------------------------------------
    def _order_flow(self):
        return self.env['ir.config_parameter'].sudo().get_param('ff_base.order_flow') or 'direct'

    def _viewer(self):
        return self.env['hr.employee'].sudo().browse(self.env.context.get('ff_report_viewer'))

    def _utc_bounds(self, start, end):
        """Naive-UTC [from, to) covering the local days ``start``..``end``."""
        low, _unused = self._viewer()._ff_day_bounds(start)
        _unused, high = self._viewer()._ff_day_bounds(end)
        return low, high

    @staticmethod
    def _local(employee, value):
        return employee._ff_to_local(value) if value else None

    @staticmethod
    def _label(record, field):
        return dict(record._fields[field]._description_selection(record.env)).get(record[field]) or ''

    # ------------------------------------------------------------------
    # Builders
    # ------------------------------------------------------------------
    def _attendance(self, employees, start, end):
        low, high = self._utc_bounds(start - timedelta(days=1), end)
        records = self.env['hr.attendance'].sudo().search(
            [('employee_id', 'in', employees.ids), ('check_in', '>=', low), ('check_in', '<', high)],
            order='check_in desc')
        tracks = {}
        if 'ff.daily.track' in self.env:
            for track in self.env['ff.daily.track'].sudo().search(
                    [('employee_id', 'in', employees.ids), ('date', '>=', start), ('date', '<=', end)]):
                tracks[(track.employee_id.id, track.date)] = track.distance_km
        rows, seen = [], set()
        for att in records.sorted('check_in'):
            local_in = self._local(att.employee_id, att.check_in)
            day = local_in.date()
            if not start <= day <= end:
                continue
            first_of_day = (att.employee_id.id, day) not in seen
            seen.add((att.employee_id.id, day))
            rows.append({
                'date': day.isoformat(), 'employee': att.employee_id.name,
                'check_in': local_in.strftime('%H:%M'),
                'check_out': self._local(att.employee_id, att.check_out).strftime('%H:%M') if att.check_out else None,
                'hours': round(att.worked_hours or 0.0, 2),
                # A day split over several punches still counts its kilometres once.
                'km': round(tracks.get((att.employee_id.id, day), 0.0), 1) if first_of_day else 0.0,
                'status': 'Checked out' if att.check_out else 'On duty',
            })
        rows.reverse()
        return rows

    def _visits(self, employees, start, end):
        low, high = self._utc_bounds(start, end)
        visits = self.env['ff.visit'].sudo().search(
            [('employee_id', 'in', employees.ids), ('check_in_at', '>=', low), ('check_in_at', '<', high)],
            order='check_in_at desc')
        rows = []
        for visit in visits:
            local_in = self._local(visit.employee_id, visit.check_in_at)
            rows.append({
                'date': local_in.date().isoformat(), 'employee': visit.employee_id.name,
                'customer': visit.partner_id.display_name,
                'check_in': local_in.strftime('%H:%M'),
                'check_out': self._local(visit.employee_id, visit.check_out_at).strftime('%H:%M')
                if visit.check_out_at else None,
                'minutes': visit.duration_min,
                'visit_type': self._label(visit, 'visit_type') if 'visit_type' in visit._fields else '',
                'distance': visit.distance_m,
                'outcome': visit.outcome_id.name or '',
            })
        return rows

    def _orders(self, employees, start, end):
        low, high = self._utc_bounds(start, end)
        orders = self.env['sale.order'].sudo().search(
            [('ff_employee_id', 'in', employees.ids), ('date_order', '>=', low), ('date_order', '<', high)],
            order='date_order desc')
        company = self._viewer().company_id
        return [{
            'date': self._local(order.ff_employee_id, order.date_order).date().isoformat(),
            'employee': order.ff_employee_id.name, 'number': order.name,
            'customer': order.partner_id.display_name,
            # Everything in the company currency, so the column can be totalled.
            'amount': order.currency_id._convert(order.amount_total, company.currency_id, company,
                                                 order.date_order.date()),
            'status': self._label(order, 'state'),
        } for order in orders]

    def _demands(self, employees, start, end):
        low, high = self._utc_bounds(start, end)
        demands = self.env['ff.demand'].sudo().search(
            [('employee_id', 'in', employees.ids), ('date', '>=', low), ('date', '<', high)], order='date desc')
        return [{
            'date': self._local(demand.employee_id, demand.date).date().isoformat(),
            'employee': demand.employee_id.name, 'number': demand.name,
            'customer': demand.partner_id.display_name, 'distributor': demand.distributor_id.display_name or '',
            'units': demand.quantity_total,
            'amount': 0.0 if demand.state == 'cancelled' else demand.amount_total,
            'status': self._label(demand, 'state'),
        } for demand in demands]

    def _collections(self, employees, start, end):
        low, high = self._utc_bounds(start, end)
        records = self.env['ff.collection'].sudo().search(
            [('employee_id', 'in', employees.ids), ('date', '>=', low), ('date', '<', high)], order='date desc')
        return [{
            'date': self._local(rec.employee_id, rec.date).date().isoformat(),
            'employee': rec.employee_id.name, 'customer': rec.partner_id.display_name,
            'mode': rec.mode_id.name, 'reference': rec.reference or '',
            'amount': 0.0 if rec.state == 'cancelled' else rec.amount,
            'status': self._label(rec, 'state'),
        } for rec in records]

    def _expenses(self, employees, start, end):
        records = self.env['ff.expense.claim'].sudo().search(
            [('employee_id', 'in', employees.ids), ('date', '>=', start), ('date', '<=', end)], order='date desc')
        return [{
            'date': rec.date.isoformat(), 'reference': rec.ff_reference or '', 'employee': rec.employee_id.name,
            'category': rec.category_id.name, 'amount': rec.amount, 'status': self._label(rec, 'state'),
        } for rec in records]

    def _allowances(self, employees, start, end):
        records = self.env['ff.allowance.claim'].sudo().search(
            [('employee_id', 'in', employees.ids), ('date', '>=', start), ('date', '<=', end)], order='date desc')
        return [{
            'date': rec.date.isoformat(), 'reference': rec.ff_reference or '', 'employee': rec.employee_id.name,
            'km': round(rec.distance_km, 1), 'visits': rec.visit_count, 'amount': rec.amount,
            'status': self._label(rec, 'state'),
        } for rec in records]

    def _leaves(self, employees, start, end):
        records = self.env['hr.leave'].sudo().search(
            [('employee_id', 'in', employees.ids), ('request_date_from', '<=', end),
             ('request_date_to', '>=', start)], order='request_date_from desc')
        return [{
            'employee': rec.employee_id.name, 'type': rec.holiday_status_id.name,
            'date': rec.request_date_from.isoformat() if rec.request_date_from else None,
            'date_to': rec.request_date_to.isoformat() if rec.request_date_to else None,
            'days': rec.number_of_days, 'status': self._label(rec, 'state'),
        } for rec in records]

    def _distance(self, employees, start, end):
        tracks = self.env['ff.daily.track'].sudo().search(
            [('employee_id', 'in', employees.ids), ('date', '>=', start), ('date', '<=', end)], order='date desc')
        return [{
            'date': track.date.isoformat(), 'employee': track.employee_id.name,
            'km': round(track.distance_km, 1),
            'first': self._local(track.employee_id, track.first_ping_at).strftime('%H:%M')
            if track.first_ping_at else None,
            'last': self._local(track.employee_id, track.last_ping_at).strftime('%H:%M')
            if track.last_ping_at else None,
            'pings': track.ping_count,
        } for track in tracks]

    def _customers(self, employees, start, end):
        low, high = self._utc_bounds(start, end)
        partners = self.env['res.partner'].sudo().with_context(active_test=False).search(
            [('ff_created_by_employee_id', 'in', employees.ids), ('create_date', '>=', low),
             ('create_date', '<', high)], order='create_date desc')
        return [{
            'date': self._local(partner.ff_created_by_employee_id, partner.create_date).date().isoformat(),
            'employee': partner.ff_created_by_employee_id.name, 'customer': partner.display_name,
            'category': partner.ff_category_id.name or '', 'city': partner.city or '',
            'phone': partner.phone or '', 'status': self._label(partner, 'ff_approval_state'),
        } for partner in partners]

    # ------------------------------------------------------------------
    # Excel
    # ------------------------------------------------------------------
    @api.model
    def ff_xlsx(self, data, who):
        """The report payload as an .xlsx file (bytes)."""
        import io

        import xlsxwriter

        buffer = io.BytesIO()
        book = xlsxwriter.Workbook(buffer, {'in_memory': True})
        sheet = book.add_worksheet(data['title'][:31])
        bold = book.add_format({'bold': True})
        title = book.add_format({'bold': True, 'font_size': 14})
        head = book.add_format({'bold': True, 'bg_color': '#E8EFFF', 'border': 1})
        money = book.add_format({'num_format': '#,##0.00'})
        number = book.add_format({'num_format': '#,##0.##'})
        date_fmt = book.add_format({'num_format': 'dd-mm-yyyy'})
        formats = {MONEY: money, HOURS: number, KM: number, NUMBER: number}

        sheet.write(0, 0, data['title'], title)
        sheet.write(1, 0, '%s to %s  -  %s' % (data['start'], data['end'], who))
        columns = data['columns']
        for index, column in enumerate(columns):
            label = column['label'] + (' (%s)' % data['currency'] if column['type'] == MONEY else '')
            sheet.write(3, index, label, head)
            sheet.set_column(index, index, 24 if column['type'] == TEXT else 14)
        row_no = 4
        for row in data['rows']:
            for index, column in enumerate(columns):
                value = row.get(column['key'])
                if value is None or value == '':
                    continue
                if column['type'] == DATE:
                    sheet.write_datetime(row_no, index, datetime.strptime(value, '%Y-%m-%d'), date_fmt)
                elif column['type'] in formats:
                    sheet.write_number(row_no, index, value, formats[column['type']])
                else:
                    sheet.write(row_no, index, value)
            row_no += 1
        if data['totals']:
            sheet.write(row_no, 0, 'Total', bold)
            for index, column in enumerate(columns):
                if column['key'] in data['totals']:
                    sheet.write_number(row_no, index, data['totals'][column['key']], formats.get(column['type'], bold))
        sheet.freeze_panes(4, 0)
        book.close()
        return buffer.getvalue()
