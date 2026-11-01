"""Keep the sale price on PTS while the company sells through distributors.

On the demand flow the customer on a quotation is the distributor, so the price
Odoo should reach for by default is PTS. Rather than teach every screen about
trade prices, the sale price simply follows PTS whenever that flow is on: any
quotation, price list rule or report that reads the sale price then quotes the
distributor correctly.
"""
from odoo import api, models

from .ff_demand import order_flow


class ProductTemplate(models.Model):
    _inherit = 'product.template'

    @api.model_create_multi
    def create(self, vals_list):
        products = super().create(vals_list)
        products._ff_sync_sale_price()
        return products

    def write(self, vals):
        result = super().write(vals)
        # Only when PTS itself moved, so a deliberate sale price is left alone.
        if 'ff_pts' in vals:
            self._ff_sync_sale_price()
        return result

    def _ff_sync_sale_price(self):
        """Sale price follows PTS on the demand flow. Silent on the direct flow."""
        if order_flow(self.env) != 'demand' or self.env.context.get('ff_skip_price_sync'):
            return
        for product in self:
            if product.ff_pts and product.list_price != product.ff_pts:
                super(ProductTemplate, product.with_context(ff_skip_price_sync=True)).write(
                    {'list_price': product.ff_pts})

    def action_ff_apply_pts_price(self):
        """Backfill: put PTS on the sale price of every product chosen."""
        products = self or self.search([('ff_pts', '>', 0)])
        for product in products.filtered(lambda p: p.ff_pts and p.list_price != p.ff_pts):
            super(ProductTemplate, product.with_context(ff_skip_price_sync=True)).write(
                {'list_price': product.ff_pts})
        return True
