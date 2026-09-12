from odoo import fields, models


class ResConfigSettings(models.TransientModel):
    _inherit = 'res.config.settings'

    ff_collection_max_days = fields.Integer(
        string='Deposit Within (days)', config_parameter='ff_collections.max_days', default=3,
        help='After this many days holding money, field staff cannot check in until they hand it over. 0 = no limit.')
    ff_collection_max_amount = fields.Float(
        string='Maximum Held Amount', config_parameter='ff_collections.max_amount',
        help='When the money held goes above this, field staff cannot check in until they hand it over. 0 = no limit.')
