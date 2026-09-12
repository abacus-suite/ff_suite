from odoo import api, fields, models


class ProductTemplate(models.Model):
    """Trade prices as the field knows them.

    A pharma or FMCG product travels through three prices: the company sells to
    the stockist at PTS, the stockist sells to the retailer at PTR, and the
    retailer sells to the patient at MRP. Field staff quote PTR, the office
    quotes PTS to the distributor, and the margin between them is what a
    retailer asks about first.
    """
    _inherit = 'product.template'

    ff_sku_code = fields.Char(string='SKU Short Code', index=True, copy=False,
                              help='Short code shown in the field app and order reports, e.g. LR, CP.')
    ff_show_in_app = fields.Boolean(string='Available in Field App', default=True)

    ff_mrp = fields.Monetary(string='MRP', currency_field='currency_id',
                             help='Maximum retail price printed on the pack.')
    ff_pts = fields.Monetary(string='PTS', currency_field='currency_id',
                             help='Price to stockist: what the distributor pays the company.')
    ff_ptr = fields.Monetary(string='PTR', currency_field='currency_id',
                             help='Price to retailer: what the outlet pays the distributor.')
    ff_retail_margin = fields.Float(string='Retail Margin %', compute='_compute_ff_margins', store=True,
                                    help='What the outlet earns between PTR and MRP.')
    ff_stockist_margin = fields.Float(string='Stockist Margin %', compute='_compute_ff_margins', store=True,
                                      help='What the distributor earns between PTS and PTR.')

    @api.depends('ff_mrp', 'ff_pts', 'ff_ptr')
    def _compute_ff_margins(self):
        for product in self:
            product.ff_retail_margin = self._margin(product.ff_ptr, product.ff_mrp)
            product.ff_stockist_margin = self._margin(product.ff_pts, product.ff_ptr)

    def _margin(self, cost, sale):
        """Margin on the selling price, the way the trade quotes it."""
        return round((sale - cost) / sale * 100.0, 2) if cost and sale else 0.0


class ProductProduct(models.Model):
    _inherit = 'product.product'

    def ff_field_price(self):
        """What the field quotes an outlet: PTR when it is set, else the sale price."""
        self.ensure_one()
        return self.product_tmpl_id.ff_ptr or self.lst_price

    def ff_distributor_price(self):
        """What the office quotes a distributor: PTS when it is set, else the sale price."""
        self.ensure_one()
        return self.product_tmpl_id.ff_pts or self.lst_price
