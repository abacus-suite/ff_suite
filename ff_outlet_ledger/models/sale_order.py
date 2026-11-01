"""When a distributor accepts an order, both sets of invoices appear on their own."""
from datetime import timedelta

from odoo import fields, models
from odoo.exceptions import UserError


class SaleOrder(models.Model):
    _inherit = 'sale.order'

    def action_confirm(self):
        result = super().action_confirm()
        for order in self.sudo().filtered(lambda o: o.ff_source == 'app' and o.ff_demand_ids):
            order._ff_auto_invoice()
        return result

    def _ff_auto_invoice(self, force=False):
        """The company's invoice to the distributor, posted; and each outlet's invoice, ready to collect.

        A failure is written on the order and never stops the confirmation, so the
        office can finish it by hand.
        """
        self.ensure_one()
        if not force and (self.env['ir.config_parameter'].sudo().get_param('ff_base.auto_invoice') or 'yes') == 'no':
            return
        try:
            with self.env.cr.savepoint():
                self._ff_company_invoice()
                # Outlets are billed on delivery now; only an older order, from before requests, raises them here.
                if not self.ff_demand_ids.filtered('request_id'):
                    self.env['ff.outlet.invoice'].ff_from_order(self)
        except Exception as error:  # noqa: BLE001 - the confirmation must stand
            self.message_post(body=self.env._('The invoices could not be created automatically: %s', error))

    def _ff_company_invoice(self):
        self.ensure_one()
        if self.invoice_ids.filtered(lambda m: m.state != 'cancel'):
            return self.invoice_ids
        lines = self.order_line.filtered(lambda l: not l.display_type and l.product_uom_qty)
        values = self._prepare_invoice()
        values['invoice_date'] = fields.Date.context_today(self)
        values['invoice_line_ids'] = [
            (0, 0, line._prepare_invoice_line(sequence=index, quantity=line.product_uom_qty))
            for index, line in enumerate(lines, 1)]
        icp = self.env['ir.config_parameter'].sudo()
        credit_days = getattr(self.partner_id.commercial_partner_id, 'ff_credit_days', 0) or 0
        if credit_days > 0:
            # The credit days agreed with this distributor decide when the invoice falls due.
            values['invoice_payment_term_id'] = False
            values['invoice_date_due'] = values['invoice_date'] + timedelta(days=credit_days)
        elif not values.get('invoice_payment_term_id'):
            term = self.env['account.payment.term'].browse(int(icp.get_param('ff_base.invoice_payment_term_id') or 0)).exists()
            if term:
                values['invoice_payment_term_id'] = term.id
            else:
                values['invoice_date_due'] = values['invoice_date'] + timedelta(
                    days=int(icp.get_param('ff_base.invoice_due_days') or 30))
        move = self.env['account.move'].sudo().with_company(self.company_id).create(values)
        move.action_post()
        return move

    def action_ff_create_invoices(self):
        """Create the invoices by hand: for an order confirmed before this was automatic, or with it switched off."""
        for order in self.sudo():
            if order.state not in ('sale', 'done'):
                raise UserError(self.env._('%s is not confirmed yet.', order.name))
            order._ff_auto_invoice(force=True)
        return True
