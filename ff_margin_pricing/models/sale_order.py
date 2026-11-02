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
        return order
