from odoo import fields, models


class ResConfigSettings(models.TransientModel):
    _inherit = 'res.config.settings'

    ff_ola_monthly = fields.Float(string='OLA per Month', config_parameter='ff_allowance.ola_monthly', default=1000)
    ff_ola_days = fields.Integer(string='Days in the OLA Month', config_parameter='ff_allowance.ola_days', default=26)
    ff_ola_half_hours = fields.Float(string='Half OLA From (hours)', config_parameter='ff_allowance.ola_half_hours',
                                     default=4)
    ff_ola_full_hours = fields.Float(string='Full OLA From (hours)', config_parameter='ff_allowance.ola_full_hours',
                                     default=8)
