"""Reports behind the download button of the employee's own screens: samples, events and receivables."""
from odoo import fields, models

from .ff_app_report import DATE, HOURS, MONEY, NUMBER, STATUS, col

EVENT_STATES = {'draft': 'Draft', 'running': 'Running', 'on_hold': 'On hold', 'done': 'Completed'}


class FfAppReportEmployee(models.AbstractModel):
    _inherit = 'ff.app.report'

    def _definitions(self):
        defs = super()._definitions()
        if 'ff.sample.move' in self.env:
            defs['samples'] = ('Samples', 'Samples taken and given', 'redeem', 'ff.sample.move', [
                col('date', 'Date', DATE), col('employee', 'Employee'), col('product', 'Flavour'),
                col('direction', 'Movement', STATUS), col('quantity', 'Bottles', NUMBER, True),
                col('contact', 'Contact'), col('source', 'Taken from')], self._samples)
        if 'ff.event' in self.env:
            defs['events'] = ('Events', 'Sampling and sales events', 'celebration', 'ff.event', [
                col('date', 'Start', DATE), col('name', 'Event'), col('employee', 'Organiser'),
                col('location', 'Location'), col('days', 'Days', NUMBER, True),
                col('coupons', 'Coupons', NUMBER, True), col('cash', 'Cash received', MONEY, True),
                col('status', 'Status', STATUS)], self._events)
        if 'account.move' in self.env:
            defs['receivables'] = ('Receivables', 'Open invoices of the customers', 'account_balance_wallet', 'account.move', [
                col('date', 'Invoice date', DATE), col('number', 'Invoice'), col('customer', 'Customer'),
                col('due_date', 'Due date', DATE), col('amount', 'Invoice amount', MONEY, True),
                col('residual', 'Amount due', MONEY, True), col('late', 'Days late', NUMBER),
                col('status', 'Status', STATUS)], self._receivables)
        if 'ff.da.claim' in self.env:
            defs['da'] = ('Daily allowance', 'Daily allowance claims per day', 'restaurant', 'ff.da.claim', [
                col('date', 'Date', DATE), col('employee', 'Employee'), col('kind', 'Where', STATUS),
                col('visits', 'Visits', NUMBER, True), col('outside', 'Outside visits', NUMBER, True),
                col('rate', 'Rate', MONEY), col('amount', 'Amount', MONEY, True), col('status', 'Status', STATUS)],
                self._da)
        if 'ff.ola.claim' in self.env:
            defs['ola'] = ('OLA', 'Monthly allowance by the hours worked', 'timer', 'ff.ola.claim', [
                col('date', 'Date', DATE), col('employee', 'Employee'), col('hours', 'Hours', HOURS, True),
                col('kind', 'Allowance', STATUS), col('day_rate', 'Full day', MONEY),
                col('amount', 'Amount', MONEY, True)], self._ola)
        if 'ff.expense.request' in self.env:
            defs['payment_requests'] = ('Payment requests', 'Requests paid directly by accounts', 'request_quote',
                                        'ff.expense.request', [
                col('date', 'Date', DATE), col('employee', 'Employee'), col('reference', 'Request'),
                col('category', 'Category'), col('document', 'Document'), col('amount', 'Amount', MONEY, True),
                col('status', 'Status', STATUS)], self._payment_requests)
        return defs

    def _da(self, employees, start, end):
        records = self.env['ff.da.claim'].sudo().search(
            [('employee_id', 'in', employees.ids), ('date', '>=', start), ('date', '<=', end)], order='date desc')
        kinds = dict(records._fields['kind'].selection)
        return [{
            'date': rec.date.isoformat(), 'employee': rec.employee_id.name, 'kind': kinds.get(rec.kind, rec.kind or ''),
            'visits': rec.visit_count, 'outside': rec.outside_count, 'rate': rec.rate, 'amount': rec.amount,
            'status': self._label(rec, 'state'),
        } for rec in records]

    def _ola(self, employees, start, end):
        records = self.env['ff.ola.claim'].sudo().search(
            [('employee_id', 'in', employees.ids), ('date', '>=', start), ('date', '<=', end)], order='date desc')
        kinds = dict(records._fields['kind'].selection)
        return [{
            'date': rec.date.isoformat(), 'employee': rec.employee_id.name, 'hours': round(rec.hours or 0.0, 2),
            'kind': kinds.get(rec.kind, rec.kind or ''), 'day_rate': rec.day_rate, 'amount': rec.amount,
        } for rec in records]

    def _payment_requests(self, employees, start, end):
        records = self.env['ff.expense.request'].sudo().search(
            [('employee_id', 'in', employees.ids), ('date', '>=', start), ('date', '<=', end)], order='date desc')
        documents = dict(records._fields['document'].selection)
        return [{
            'date': rec.date.isoformat(), 'employee': rec.employee_id.name, 'reference': rec.name or '',
            'category': ' / '.join(x for x in (rec.category_id.name, rec.sub_category_id.name) if x),
            'document': documents.get(rec.document, rec.document or ''), 'amount': rec.amount,
            'status': self._label(rec, 'state'),
        } for rec in records]

    def _samples(self, employees, start, end):
        low, high = self._utc_bounds(start, end)
        moves = self.env['ff.sample.move'].sudo().search([
            ('employee_id', 'in', employees.ids), ('date', '>=', low), ('date', '<', high)], order='date desc')
        sources = {'company': 'Company', 'distributor': 'Distributor', 'outlet': 'Outlet'}
        return [{
            'date': self._local(m.employee_id, m.date).date().isoformat(), 'employee': m.employee_id.name,
            'product': m.product_id.display_name, 'direction': 'Taken' if m.direction == 'in' else 'Given',
            'quantity': m.quantity, 'contact': m.partner_id.display_name or '',
            'source': sources.get(m.source_type, '') if m.direction == 'in' else '',
        } for m in moves]

    def _events(self, employees, start, end):
        events = self.env['ff.event'].sudo().search([
            '|', ('employee_id', 'in', employees.ids), ('staff_ids', 'in', employees.ids),
            ('date_start', '>=', start), ('date_start', '<=', end)], order='date_start desc')
        return [{
            'date': e.date_start.isoformat() if e.date_start else None, 'name': e.name,
            'employee': e.employee_id.name, 'location': e.location or '', 'days': len(e.day_ids),
            'coupons': sum(e.day_ids.mapped('coupons_used')), 'cash': round(sum(e.day_ids.mapped('cash_received')), 2),
            'status': EVENT_STATES.get(e.state, e.state),
        } for e in events]

    def _receivables(self, employees, start, end):
        today = fields.Date.context_today(self)
        rows = []
        moves = self.env['account.move'].sudo().search([
            ('move_type', '=', 'out_invoice'), ('state', '=', 'posted'),
            ('payment_state', 'in', ('not_paid', 'partial')), ('invoice_date', '<=', end),
            ('invoice_line_ids.sale_line_ids.order_id.ff_employee_id', 'in', employees.ids)], order='invoice_date_due')
        for m in moves:
            due = m.invoice_date_due
            rows.append({
                'date': m.invoice_date.isoformat() if m.invoice_date else None, 'number': m.name,
                'customer': m.partner_id.commercial_partner_id.display_name,
                'due_date': due.isoformat() if due else None, 'amount': m.amount_total_signed,
                'residual': m.amount_residual_signed, 'late': max((today - due).days, 0) if due else 0,
                'status': 'Part paid' if m.payment_state == 'partial' else 'Open'})
        if 'ff.outlet.invoice' in self.env:
            for inv in self.env['ff.outlet.invoice'].sudo().search([
                    ('employee_id', 'in', employees.ids), ('state', 'in', ('open', 'partial')),
                    ('date', '<=', end)], order='due_date'):
                due = inv.due_date
                rows.append({
                    'date': inv.date.isoformat() if inv.date else None, 'number': inv.name,
                    'customer': inv.partner_id.display_name, 'due_date': due.isoformat() if due else None,
                    'amount': inv.amount_total, 'residual': inv.amount_pending,
                    'late': max((today - due).days, 0) if due else 0,
                    'status': 'Part paid' if inv.state == 'partial' else 'Open'})
        return rows
