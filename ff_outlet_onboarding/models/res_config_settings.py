from odoo import fields, models


class ResConfigSettings(models.TransientModel):
    _inherit = 'res.config.settings'

    ff_ask_missing_details = fields.Boolean(
        string='Ask for Missing Details', config_parameter='ff_base.ask_missing_details',
        help='When an onboarded outlet or distributor is visited and a required detail is still missing, the person '
             'fills it in first. Only then can they visit it from any task, or create a PO or a collection.')
