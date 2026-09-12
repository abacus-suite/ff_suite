from odoo import fields, models


class ResConfigSettings(models.TransientModel):
    _inherit = 'res.config.settings'

    ff_map_free_loads = fields.Integer(
        string='Free Map Loads / Month', config_parameter='ff_base.map_free_loads', default=10000)
    ff_map_free_tiles = fields.Integer(
        string='Free Tiles / Month', config_parameter='ff_base.map_free_tiles', default=100000)
    ff_map_price_loads = fields.Float(
        string='Price per 1000 Map Loads', config_parameter='ff_base.map_price_loads', default=620.0)
    ff_map_price_tiles = fields.Float(
        string='Price per 1000 Tiles', config_parameter='ff_base.map_price_tiles', default=53.0)
    ff_map_budget = fields.Float(
        string='Monthly Map Budget', config_parameter='ff_base.map_budget',
        help='The live map warns once the estimated cost passes this. 0 = no budget.')
    ff_map_free_geocode = fields.Integer(
        string='Free Address Lookups / Month', config_parameter='ff_base.map_free_geocode', default=10000)
    ff_map_price_geocode = fields.Float(
        string='Price per 1000 Address Lookups', config_parameter='ff_base.map_price_geocode', default=440.0)
