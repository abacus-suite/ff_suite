from odoo import fields, models


class ResConfigSettings(models.TransientModel):
    _inherit = 'res.config.settings'

    ff_beats_per_week = fields.Integer(
        string='Beats per Week', config_parameter='ff_base.beats_per_week', default=6,
        help='The most different beats one person may plan in a week. A week is Monday to Sunday. '
             'Zero means no limit. Customer-picked days have no beat and do not count.')
    ff_beat_approval = fields.Boolean(
        string='New Routes Need Approval', config_parameter='ff_base.beat_approval',
        help='A route drawn in the app waits for a manager before anybody can plan from it. '
             'Off, it is taken on trust and can be used straight away - the field is the side '
             'that finds out a patch of town has been missed.')
