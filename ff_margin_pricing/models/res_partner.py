from odoo import fields, models


class ResPartner(models.Model):
    _inherit = 'res.partner'

    ff_margin = fields.Float(
        string='Margin %', digits=(8, 2),
        help='Percentage of MRP. A distributor passes this margin to the outlets it supplies (outlets buy at '
             'MRP less it). An outlet sells at MRP less its own margin.')
