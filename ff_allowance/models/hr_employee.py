from odoo import fields, models


class HrEmployee(models.Model):
    _inherit = 'hr.employee'

    ff_allowance_policy_id = fields.Many2one(
        'ff.allowance.policy', string='Allowance Policy',
        help='Leave empty to use the policy of the employee\'s department (or the company default).')
