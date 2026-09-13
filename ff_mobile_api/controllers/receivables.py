"""Money customers owe: open invoices with due and overdue, ageing, and a statement of account.

Only customers the employee can see (their Data Access) are included, in the
company currency, from posted accounting entries.
"""
from datetime import timedelta

from odoo import fields, http
from odoo.http import request

from odoo.addons.ff_base.tools import to_iso

from .clients import client_domain, to_int, visible_client
from .common import ApiError, api_route, ok, ref

BUCKETS = [('not_due', 'Not due'), ('1_30', '1–30 days'), ('31_60', '31–60 days'),
           ('61_90', '61–90 days'), ('90_plus', 'Over 90 days')]


def _bucket(days_overdue):
    if days_overdue <= 0:
        return 'not_due'
    if days_overdue <= 30:
        return '1_30'
    if days_overdue <= 60:
        return '31_60'
    if days_overdue <= 90:
        return '61_90'
    return '90_plus'


def _check_accounting():
    if 'account.move' not in request.env:
        raise ApiError('Invoicing is not installed.', 404, 'not_found')


class FieldForceReceivablesApi(http.Controller):

    @api_route('/api/v1/receivables', methods=('GET',))
    def receivables(self, employee, filter='open', q=None, partner_id=None, limit=None, **kw):
        """Open invoices. filter: open (all unpaid), overdue, due_soon (next 7 days)."""
        _check_accounting()
        env = request.env
        today = employee._ff_today()
        company = employee.company_id
        if partner_id:
            partners = visible_client(employee, to_int(partner_id))
        else:
            domain = client_domain(employee)
            if q:
                domain = domain + ['|', ('name', 'ilike', q), ('ff_client_code', 'ilike', q)]
            partners = env['res.partner'].sudo().search(domain)
        families = partners.mapped('commercial_partner_id')
        move_domain = [
            ('partner_id', 'child_of', families.ids), ('move_type', 'in', ('out_invoice', 'out_refund')),
            ('state', '=', 'posted'), ('payment_state', 'in', ('not_paid', 'partial')),
            ('company_id', '=', company.id),
        ]
        if filter == 'overdue':
            move_domain.append(('invoice_date_due', '<', today))
        elif filter == 'due_soon':
            move_domain += [('invoice_date_due', '>=', today), ('invoice_date_due', '<=', today + timedelta(days=7))]
        moves = env['account.move'].sudo().search(move_domain, order='invoice_date_due asc, id asc',
                                                  limit=min(to_int(limit) or 200, 500)) if families else env['account.move']
        ageing = {key: 0.0 for key, _label in BUCKETS}
        rows, total, overdue = [], 0.0, 0.0
        for move in moves:
            residual = move.amount_residual_signed
            late_days = (today - move.invoice_date_due).days if move.invoice_date_due else 0
            bucket = _bucket(late_days)
            ageing[bucket] += residual
            total += residual
            if late_days > 0 and residual > 0:
                overdue += residual
            rows.append({
                'id': move.id,
                'number': move.name,
                'customer': ref(move.partner_id.commercial_partner_id),
                'date': to_iso(move.invoice_date),
                'due_date': to_iso(move.invoice_date_due),
                'amount': round(move.amount_total_signed, 2),
                'residual': round(residual, 2),
                'days_overdue': max(late_days, 0),
                'bucket': bucket,
                'is_refund': move.move_type == 'out_refund',
                'salesperson': move.invoice_user_id.name or None,
            })
        return ok({
            'currency': company.currency_id.name,
            'filter': filter,
            'total': round(total, 2),
            'overdue': round(overdue, 2),
            'count': len(rows),
            'ageing': [{'key': key, 'label': label, 'amount': round(ageing[key], 2)} for key, label in BUCKETS],
            'invoices': rows,
        })

    @api_route('/api/v1/clients/<int:partner_id>/soa', methods=('GET',))
    def statement(self, employee, partner_id, start=None, end=None, **kw):
        """Statement of account: opening balance, every posted receivable entry in the period, closing balance."""
        _check_accounting()
        partner = visible_client(employee, partner_id).commercial_partner_id
        today = employee._ff_today()
        try:
            end_date = fields.Date.to_date(end) if end else today
            start_date = fields.Date.to_date(start) if start else end_date.replace(day=1) - timedelta(days=90)
        except ValueError:
            raise ApiError('Dates must be YYYY-MM-DD.')
        company = employee.company_id
        Line = request.env['account.move.line'].sudo()
        base = [('partner_id', 'child_of', partner.id), ('account_id.account_type', '=', 'asset_receivable'),
                ('parent_state', '=', 'posted'), ('company_id', '=', company.id)]
        opening = sum(Line.search(base + [('date', '<', start_date)]).mapped('balance'))
        running = opening
        rows = []
        for line in Line.search(base + [('date', '>=', start_date), ('date', '<=', end_date)], order='date asc, id asc'):
            running += line.balance
            move = line.move_id
            kind = {'out_invoice': 'Invoice', 'out_refund': 'Credit note'}.get(
                move.move_type, 'Payment' if line.credit else 'Adjustment')
            rows.append({
                'date': to_iso(line.date),
                'number': move.name,
                'kind': kind,
                'reference': move.ref or line.name or None,
                'due_date': to_iso(line.date_maturity),
                'debit': round(line.debit, 2),
                'credit': round(line.credit, 2),
                'balance': round(running, 2),
            })
        return ok({
            'customer': ref(partner),
            'currency': company.currency_id.name,
            'start': start_date.isoformat(),
            'end': end_date.isoformat(),
            'opening': round(opening, 2),
            'closing': round(running, 2),
            'debit': round(sum(r['debit'] for r in rows), 2),
            'credit': round(sum(r['credit'] for r in rows), 2),
            'lines': rows,
        })
