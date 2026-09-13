from odoo import fields, models


class ResConfigSettings(models.TransientModel):
    _inherit = 'res.config.settings'

    ff_targets_who_splits = fields.Selection([
        ('managers', 'Owners split their own targets (office and managers)'),
        ('office', 'Only the office sets targets'),
    ], string='Who Splits Targets', config_parameter='ff_targets.who_splits', default='managers')
    ff_targets_split_mode = fields.Selection([
        ('not_above', 'Cannot split more than was given'),
        ('free', 'Free (splits may add up to more)'),
    ], string='Splitting Rule', config_parameter='ff_targets.split_mode', default='not_above')
    ff_targets_default_rule_id = fields.Many2one(
        'ff.incentive.rule', string='Default Incentive',
        config_parameter='ff_targets.default_rule_id',
        help='Given to new top-level targets; split targets take their parent\'s.')
