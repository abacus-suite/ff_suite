from odoo import fields, models


class HrLeaveType(models.Model):
    _inherit = 'hr.leave.type'

    ff_comp_off = fields.Boolean(
        string='Compensatory Off', copy=False,
        help='Approved overtime is added to the balance of this type, in hours.')
