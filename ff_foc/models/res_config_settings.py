from odoo import api, fields, models


class ResConfigSettings(models.TransientModel):
    _inherit = 'res.config.settings'

    ff_foc_manual_allowed = fields.Boolean(
        string='Reps May Add FOC', help='Free samples or trade FOC added by hand in the app, with a reason.')

    @api.model
    def get_values(self):
        values = super().get_values()
        values['ff_foc_manual_allowed'] = self.env['ir.config_parameter'].sudo().get_param(
            'ff_foc.manual_allowed', 'True') != 'False'
        return values

    def set_values(self):
        super().set_values()
        self.env['ir.config_parameter'].sudo().set_param(
            'ff_foc.manual_allowed', 'True' if self.ff_foc_manual_allowed else 'False')
