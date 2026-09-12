from odoo import fields, models


class ResConfigSettings(models.TransientModel):
    _inherit = 'res.config.settings'

    ff_order_flow = fields.Selection([
        ('direct', 'Direct sale order'),
        ('demand', 'Demand, then distributor quotation'),
    ], string='Order Flow', config_parameter='ff_base.order_flow', default='direct',
        help='Direct: an order taken in the app becomes a quotation for the outlet.\n'
             'Demand: the app collects demand, and the office consolidates it into '
             'quotations for the distributors who supply those outlets.')
