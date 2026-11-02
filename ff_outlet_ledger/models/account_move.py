from datetime import timedelta

from odoo import fields, models


class AccountMove(models.Model):
    _inherit = 'account.move'

    def _ff_credit_due_date(self):
        """When this customer invoice falls due: the credit days of the contact, else the default due days of the
        settings, counted from the invoice date."""
        self.ensure_one()
        partner = self.partner_id.commercial_partner_id
        base = self.invoice_date or fields.Date.context_today(self)
        days = getattr(partner, 'ff_credit_days', 0) or 0
        if days <= 0:
            days = int(self.env['ir.config_parameter'].sudo().get_param('ff_base.invoice_due_days') or 30)
        return base + timedelta(days=days)

    def action_post(self):
        # An invoice made from a sale order (a distributor's, or one raised by the field) falls due by the credit days
        # of its contact, else the default due days: not by the payment terms of the order.
        for move in self.filtered(lambda m: m.move_type == 'out_invoice' and m.state == 'draft'):
            if move.line_ids.sale_line_ids.order_id:
                move.write({'invoice_payment_term_id': False, 'invoice_date_due': move._ff_credit_due_date()})
        return super().action_post()
