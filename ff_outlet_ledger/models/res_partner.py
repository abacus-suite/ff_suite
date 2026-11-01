from odoo import fields, models


class ResPartner(models.Model):
    _inherit = 'res.partner'

    ff_earning_pct = fields.Float(
        string='Distributor Earning %', digits=(5, 2),
        help='What share of the money collected from outlets the distributor keeps as its '
             'earning. The reports work the distributor\'s earning out from this.')
