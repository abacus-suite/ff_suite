from odoo import api, models

from .product import price_basis


class SaleOrder(models.Model):
    _inherit = 'sale.order'

    @api.model
    def ff_create_from_app(self, employee, partner, data):
        """The outlet's rate from the margin formula includes the GST. The unit price of the order is that rate
        without the GST (97.30 at 5% is 92.67); the taxes of the line are then added on top as usual."""
        uuid = data.get('uuid') or False
        resent = bool(uuid and self.sudo().search_count([('ff_client_uuid', '=', uuid)]))
        order = super().ff_create_from_app(employee, partner, data)
        if not resent and price_basis(self.env) == 'margin' and not order.partner_id.sudo().ff_is_distributor:
            for line in order.sudo().order_line.filtered(
                    lambda l: l.price_unit > 0 and not getattr(l, 'ff_is_foc', False)):
                rate = sum(t.amount for t in line.tax_ids if t.amount_type == 'percent')
                if rate:
                    line.price_unit = round(line.price_unit / (1.0 + rate / 100.0), 2)
        # The contact's MRP master has the final say: each product it lists is sold at the price entered there (the
        # price the app shows, before tax), whatever the margin formula worked out.
        if not resent:
            contact = (order.ff_outlet_id or order.partner_id).sudo()
            mrp = contact.ff_mrp_id if 'ff_mrp_id' in contact._fields else False
            prices = {l.product_id.id: l.mrp for l in mrp.line_ids} if mrp and 'line_ids' in mrp._fields else {}
            if prices:
                for line in order.sudo().order_line.filtered(lambda l: not getattr(l, 'ff_is_foc', False)):
                    if line.product_id.id in prices and prices[line.product_id.id] > 0:
                        line.price_unit = prices[line.product_id.id]
        return order
