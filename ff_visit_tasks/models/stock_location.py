from odoo import fields, models


class StockLocation(models.Model):
    _inherit = 'stock.location'

    app_location = fields.Boolean(
        string='App Location',
        default=False,
        help='When enabled, sample collections from company stock in the mobile app will be issued from this warehouse location.',
    )
    ff_app_location = fields.Boolean(
        string='App Location',
        related='app_location',
        readonly=False,
        store=True,
    )
