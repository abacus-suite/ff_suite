"""The statement of account an outlet or a distributor is sent: every invoice with what is on it,
every payment, and what is left."""
from datetime import timedelta

from odoo import fields, models


class ResPartner(models.Model):
    _inherit = 'res.partner'

    def ff_ledger_statement(self):
        """Everything the statement shows, worked out once for the PDF and for any other reader."""
        self.ensure_one()
        partner = self.sudo()
        family = partner.commercial_partner_id
        today = fields.Date.context_today(self)
        if partner.ff_is_distributor and 'account.move' in self.env:
            return self._ff_company_statement(partner, family, today)
        return self._ff_outlet_statement(partner, family, today)

    # ------------------------------------------------------------------
    # An outlet: the distributor's invoices to it, kept here
    # ------------------------------------------------------------------
    def _ff_outlet_statement(self, partner, family, today):
        Invoice = self.env['ff.outlet.invoice'].sudo()
        since = today - timedelta(days=365)
        invoices = Invoice.search([('partner_id', 'child_of', family.id), ('state', '!=', 'cancelled')],
                                  order='date asc, id asc')
        invoices = invoices.filtered(lambda i: i.state in ('open', 'partial') or i.date >= since)
        rows, payments = [], {}
        for invoice in invoices:
            lines = []
            if invoice.demand_id:
                for line in invoice.demand_id.line_ids:
                    free = bool(getattr(line, 'is_foc', False))
                    lines.append({
                        'name': line.product_id.display_name, 'qty': line.quantity, 'price': line.price_unit,
                        'discount': 100.0 if free else (getattr(line, 'discount', 0.0) or 0.0),
                        'tax': getattr(line, 'tax_percent', 0.0) or 0.0, 'amount': line.subtotal, 'free': free,
                    })
            for pay in invoice.payment_line_ids.filtered(lambda l: l.payment_id.state != 'rejected'):
                row = payments.setdefault(pay.payment_id.id, {
                    'date': pay.payment_id.date, 'number': pay.payment_id.name,
                    'mode': pay.payment_id.mode_id.name or '', 'reference': pay.payment_id.reference or '',
                    'state': dict(pay.payment_id._fields['state'].selection).get(pay.payment_id.state, ''),
                    'amount': 0.0, 'invoices': [],
                })
                row['amount'] += pay.amount
                row['invoices'].append(invoice.name)
            rows.append({
                'number': invoice.name, 'date': invoice.date, 'due': invoice.due_date,
                'amount': invoice.amount_total, 'collected': invoice.amount_collected,
                'pending': invoice.amount_pending,
                'state': dict(invoice._fields['state'].selection).get(invoice.state),
                'overdue': invoice.overdue, 'lines': lines,
                'note': '' if lines else self.env._("Entered from the distributor's own invoice."),
            })
        distributors = invoices.mapped('distributor_id') or partner.ff_distributor_id
        return {
            'kind': 'outlet', 'partner': partner, 'from_name': ', '.join(distributors.mapped('name')) or '',
            'from_party': distributors[:1], 'from_address': self._ff_address(distributors[:1]), 'invoices': rows,
            'payments': sorted(payments.values(), key=lambda p: p['date'] or fields.Datetime.now()),
            'currency': self.env.company.currency_id, 'money': self._ff_money(self.env.company.currency_id),
            'today': today,
            'totals': self._ff_statement_totals(rows),
        }

    # ------------------------------------------------------------------
    # A distributor: the company's invoices to it, in Accounting
    # ------------------------------------------------------------------
    def _ff_company_statement(self, partner, family, today):
        Move = self.env['account.move'].sudo()
        since = today - timedelta(days=365)
        moves = Move.search([
            ('partner_id', 'child_of', family.id), ('move_type', 'in', ('out_invoice', 'out_refund')),
            ('state', '=', 'posted')], order='invoice_date asc, id asc')
        moves = moves.filtered(
            lambda m: m.payment_state in ('not_paid', 'partial') or (m.invoice_date or today) >= since)
        rows, payments = [], {}
        for move in moves:
            lines = [{
                'name': l.product_id.display_name or l.name, 'qty': l.quantity, 'price': l.price_unit,
                'discount': l.discount or 0.0,
                'tax': sum(t.amount for t in l.tax_ids if t.amount_type == 'percent'),
                'amount': l.price_subtotal, 'free': (l.discount or 0.0) >= 100.0,
            } for l in move.invoice_line_ids.filtered(lambda l: l.display_type == 'product')]
            sign = -1 if move.move_type == 'out_refund' else 1
            for pay in move._get_reconciled_payments():
                row = payments.setdefault(pay.id, {
                    'date': pay.date, 'number': pay.name, 'mode': pay.journal_id.name or '',
                    'reference': pay.memo if 'memo' in pay._fields else (getattr(pay, 'ref', '') or ''),
                    'state': self.env._('Posted'), 'amount': pay.amount, 'invoices': [],
                })
                row['invoices'].append(move.name)
            rows.append({
                'number': move.name, 'date': move.invoice_date, 'due': move.invoice_date_due,
                'amount': sign * move.amount_total, 'collected': sign * (move.amount_total - move.amount_residual),
                'pending': sign * move.amount_residual,
                'state': dict(move._fields['payment_state'].selection).get(move.payment_state, ''),
                'overdue': bool(move.invoice_date_due and move.invoice_date_due < today and move.amount_residual),
                'lines': lines, 'note': '',
            })
        return {
            'kind': 'distributor', 'partner': partner, 'from_name': self.env.company.name,
            'from_party': self.env.company.partner_id, 'from_address': self._ff_address(self.env.company.partner_id),
            'invoices': rows,
            'payments': sorted(payments.values(), key=lambda p: p['date'] or today),
            'currency': self.env.company.currency_id, 'money': self._ff_money(self.env.company.currency_id),
            'today': today,
            'totals': self._ff_statement_totals(rows),
        }

    @staticmethod
    def _ff_money(currency):
        """An amount written only with plain characters.

        Odoo re-reads the report's HTML before the PDF engine gets it, which turns a currency sign
        or a non-breaking space back into raw bytes the engine then misreads. Plain text cannot
        be misread, so the rupee is written "Rs." and any other sign is replaced by its code.
        """
        symbol = currency.symbol or ''
        sign = 'Rs.' if symbol == '\u20b9' else (symbol if symbol.isascii() and symbol else currency.name)

        def money(value):
            return '%s %s' % (sign, '{:,.2f}'.format(value or 0.0))
        return money

    @staticmethod
    def _ff_address(partner):
        return ', '.join(x for x in (partner.street, partner.street2, partner.city, partner.zip) if x) if partner else ''

    @staticmethod
    def _ff_statement_totals(rows):
        return {
            'invoiced': sum(r['amount'] for r in rows),
            'collected': sum(r['collected'] for r in rows),
            'pending': sum(r['pending'] for r in rows),
            'overdue': sum(r['pending'] for r in rows if r['overdue']),
            'count': len(rows),
        }
