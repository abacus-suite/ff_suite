from odoo import fields, models


class ProductTemplate(models.Model):
    _inherit = 'product.template'

    ff_sku_code = fields.Char(string='SKU Short Code', index=True, copy=False,
                              help='Short code shown in the field app and order reports, e.g. LR, CP.')
    ff_show_in_app = fields.Boolean(string='Available in Field App', default=True)
