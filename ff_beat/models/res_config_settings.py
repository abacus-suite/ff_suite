from odoo import fields, models


class ResConfigSettings(models.TransientModel):
    _inherit = 'res.config.settings'

    ff_beat_approval = fields.Boolean(
        string='New Routes Need Approval', config_parameter='ff_base.beat_approval',
        help='A route drawn in the app waits for a manager before anybody can plan from it. '
             'Off, it is taken on trust and can be used straight away - the field is the side '
             'that finds out a patch of town has been missed.')
