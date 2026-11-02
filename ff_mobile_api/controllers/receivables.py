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


def _reach(employee, partner_id=None):
    """The branches of the move domain: the customers this person can see and, for a list that is not of one
    customer, anything billed on an order they or their team raised. Returns ``(branches, families)``."""
    env = request.env
    if partner_id:
        partners = visible_client(employee, to_int(partner_id))
    else:
        partners = env['res.partner'].sudo().search(client_domain(employee))
    families = partners.mapped('commercial_partner_id')
    mine = (employee | employee._ff_subordinates()).ids
    reach = [[('partner_id', 'child_of', families.ids)]] if families else []
    Order = env.get('sale.order')
    if not partner_id and Order is not None and 'ff_employee_id' in Order._fields:
        reach.append([('invoice_line_ids.sale_line_ids.order_id.ff_employee_id', 'in', mine)])
    return reach, families


class FieldForceReceivablesApi(http.Controller):

    @api_route('/api/v1/receivables', methods=('GET',))
    def receivables(self, employee, filter='open', q=None, partner_id=None, limit=None, kind=None, **kw):
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
            ('move_type', 'in', ('out_invoice', 'out_refund')),
            ('state', '=', 'posted'), ('payment_state', 'in', ('not_paid', 'partial')),
            ('company_id', '=', company.id),
        ]
        # Whose money to chase: the customers this person can see, and anything
        # billed on an order they raised. The second matters on the demand flow,
        # where the invoice goes to a distributor the outlet's rep may not have
        # on their own list at all - but it is still their order to collect.
        mine = (employee | employee._ff_subordinates()).ids
        reach = [[('partner_id', 'child_of', families.ids)]] if families else []
        Order = env.get('sale.order')
        if not partner_id and Order is not None and 'ff_employee_id' in Order._fields:
            reach.append([('invoice_line_ids.sale_line_ids.order_id.ff_employee_id', 'in', mine)])
        if not reach:
            moves = env['account.move']
        else:
            move_domain += ['|'] * (len(reach) - 1) + [term for branch in reach for term in branch]
            # Outlets or distributors only, when one of the two buttons is chosen.
            if kind in ('outlet', 'distributor'):
                move_domain.append(('partner_id.commercial_partner_id.ff_category_type', '=', kind))
            if filter == 'overdue':
                move_domain.append(('invoice_date_due', '<', today))
            elif filter == 'due_soon':
                move_domain += [('invoice_date_due', '>=', today),
                                ('invoice_date_due', '<=', today + timedelta(days=7))]
            # The totals and the ageing are of every open invoice; only the list on screen is cut to ``limit``.
            moves = env['account.move'].sudo().search(
                move_domain, order='invoice_date_due asc, id asc', limit=5000)
        shown = min(to_int(limit) or 200, 500)
        ageing = {key: 0.0 for key, _label in BUCKETS}
        rows, total, overdue = [], 0.0, 0.0
        customers = {}
        for move in moves:
            residual = move.amount_residual_signed
            late_days = (today - move.invoice_date_due).days if move.invoice_date_due else 0
            bucket = _bucket(late_days)
            ageing[bucket] += residual
            total += residual
            if late_days > 0 and residual > 0:
                overdue += residual
            who = move.partner_id.commercial_partner_id
            row = customers.setdefault(who.id, {
                'customer': ref(who), 'total': 0.0, 'overdue': 0.0, 'count': 0, 'days_overdue': 0, 'bucket': 'not_due'})
            row['total'] += residual
            row['count'] += 1
            if late_days > 0 and residual > 0:
                row['overdue'] += residual
            if late_days > row['days_overdue']:
                row['days_overdue'], row['bucket'] = late_days, bucket
            if len(rows) >= shown:
                continue
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
        # Nothing owing and nothing to show is one thing; an invoice sitting in
        # draft is another, and it is the usual reason somebody says their
        # receivables are missing. Count them so the app can say so.
        drafts = 0
        if not rows and reach:
            draft_domain = [
                ('move_type', 'in', ('out_invoice', 'out_refund')),
                ('state', '=', 'draft'), ('company_id', '=', company.id),
            ] + ['|'] * (len(reach) - 1) + [term for branch in reach for term in branch]
            if kind in ('outlet', 'distributor'):
                draft_domain.append(('partner_id.commercial_partner_id.ff_category_type', '=', kind))
            drafts = env['account.move'].sudo().search_count(draft_domain)
        return ok({
            'currency': company.currency_id.name,
            'filter': filter,
            'total': round(total, 2),
            'overdue': round(overdue, 2),
            'count': len(moves),
            'draft_count': drafts,
            'ageing': [{'key': key, 'label': label, 'amount': round(ageing[key], 2)} for key, label in BUCKETS],
            'invoices': rows,
            # Contact by contact, the biggest balance first.
            'customers': sorted(
                ({**c, 'total': round(c['total'], 2), 'overdue': round(c['overdue'], 2)} for c in customers.values()),
                key=lambda c: -c['total']),
        })

    @api_route('/api/v1/receivables/invoice/<int:move_id>', methods=('GET',))
    def invoice(self, employee, move_id, **kw):
        """One open invoice: its items, payment terms, taxes and what has been paid."""
        _check_accounting()
        env = request.env
        reach, _families = _reach(employee)
        if not reach:
            raise ApiError('Invoice not found.', 404, 'not_found')
        domain = [('id', '=', move_id), ('move_type', 'in', ('out_invoice', 'out_refund')),
                  ('state', '=', 'posted')] + ['|'] * (len(reach) - 1) + [t for b in reach for t in b]
        move = env['account.move'].sudo().search(domain, limit=1)
        if not move:
            raise ApiError('Invoice not found.', 404, 'not_found')
        today = employee._ff_today()
        late = (today - move.invoice_date_due).days if move.invoice_date_due else 0
        lines = []
        for line in move.invoice_line_ids.filtered(lambda l: l.display_type == 'product'):
            lines.append({
                'product': line.product_id.display_name if line.product_id else (line.name or ''),
                'name': line.name or '',
                'qty': line.quantity, 'uom': line.product_uom_id.name or None,
                'price_unit': line.price_unit, 'discount': line.discount,
                'taxes': [t.name for t in line.tax_ids],
                'subtotal': line.price_subtotal, 'total': line.price_total,
            })
        widget = move.invoice_payments_widget or {}
        payments = [{'date': str(item.get('date') or '') or None, 'amount': item.get('amount'),
                     'name': item.get('ref') or item.get('name') or None}
                    for item in (widget.get('content', []) if isinstance(widget, dict) else [])]
        order = move.invoice_line_ids.sale_line_ids.order_id[:1]
        return ok({
            'id': move.id, 'number': move.name, 'is_refund': move.move_type == 'out_refund',
            'customer': ref(move.partner_id.commercial_partner_id),
            'billed_to': ref(move.partner_id),
            'date': to_iso(move.invoice_date), 'due_date': to_iso(move.invoice_date_due),
            'days_overdue': max(late, 0), 'bucket': _bucket(late),
            'payment_terms': move.invoice_payment_term_id.name or None,
            'payment_state': move.payment_state, 'reference': move.ref or None,
            'order': order.name or None,
            'salesperson': move.invoice_user_id.name or None,
            'currency': move.currency_id.name,
            'untaxed': move.amount_untaxed_signed, 'tax': move.amount_tax_signed,
            'total': move.amount_total_signed, 'paid': round(move.amount_total_signed - move.amount_residual_signed, 2),
            'residual': move.amount_residual_signed,
            'lines': lines, 'payments': payments, 'narration': None,
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
