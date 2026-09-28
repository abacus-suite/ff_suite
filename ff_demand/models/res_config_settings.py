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

    ff_demand_submit = fields.Boolean(
        string='Field Sends Demand to Distributor', config_parameter='ff_base.demand_submit',
        help='The usual answer for everybody. In the app they pick their demands, choose the '
             'distributor and send them on as one order, then share the printed summary. '
             'Any employee can be moved off this on their own form.')
