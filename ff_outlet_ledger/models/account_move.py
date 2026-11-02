from datetime import timedelta

from odoo import fields, models


class AccountMove(models.Model):
    _inherit = 'account.move'

    def _ff_credit_due_date(self):
        """When this customer invoice falls due by the credit days of the contact, else - when it has no real payment
        term - by the default due days of the settings. None when its own payment terms decide."""
        self.ensure_one()
        partner = self.partner_id.commercial_partner_id
        base = self.invoice_date or fields.Date.context_today(self)
        days = getattr(partner, 'ff_credit_days', 0) or 0
        if days > 0:
            return base + timedelta(days=days)
        term = self.invoice_payment_term_id
        if not term or not any((line.nb_days or 0) > 0 for line in term.line_ids):
            default = int(self.env['ir.config_parameter'].sudo().get_param('ff_base.invoice_due_days') or 30)
            return base + timedelta(days=default)
        return None

    def _ff_effective_due(self):
        """The due date receivables go by: the contact's credit days, else the default, else the payment terms."""
        self.ensure_one()
        if self.move_type not in ('out_invoice', 'out_refund'):
            return self.invoice_date_due
        return self._ff_credit_due_date() or self.invoice_date_due

    def action_post(self):
        # An invoice raised from a field order falls due by the credit days of its contact (or the default).
        for move in self.filtered(lambda m: m.move_type == 'out_invoice' and m.state == 'draft'):
            orders = move.line_ids.sale_line_ids.order_id
            if orders and any(getattr(order, 'ff_source', False) for order in orders):
                due = move._ff_credit_due_date()
                if due:
                    move.write({'invoice_payment_term_id': False, 'invoice_date_due': due})
        return super().action_post()
