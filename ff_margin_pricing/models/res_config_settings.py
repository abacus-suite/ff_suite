from odoo import fields, models


class ResConfigSettings(models.TransientModel):
    _inherit = 'res.config.settings'

    ff_price_basis = fields.Selection([
        ('product', 'Product prices (PTS / PTR on each product)'),
        ('margin', 'MRP less the margin % of the contact'),
    ], string='Pricing Basis', config_parameter='ff_base.price_basis', default='product',
        help='Product prices: each product has its own PTS and PTR.\n'
             'Margin %: the product only needs its MRP. An outlet pays MRP less its margin %, and a '
             'distributor pays MRP less the company total margin %.')
    ff_total_margin = fields.Float(related='company_id.ff_total_margin', readonly=False)
