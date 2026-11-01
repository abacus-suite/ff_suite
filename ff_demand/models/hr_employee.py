"""Who may send demand on to a distributor from the phone.

Consolidating a day's demand into an order the distributor will supply is a
commercial act, not a field one, so it is not given to everybody. The company
sets the usual answer and each employee may be moved off it: a senior officer
covering a territory sends their own orders, a new joiner does not.
"""
from odoo import api, fields, models


class HrEmployee(models.Model):
    _inherit = 'hr.employee'

    ff_demand_submit = fields.Selection([
        ('default', 'Follow the company setting'),
        ('yes', 'Allowed'),
        ('no', 'Not allowed'),
    ], string='Send Demand to Distributor', default='default', required=True, tracking=True,
        help='Whether this person may turn their outlet demands into an order for a distributor '
             'in the app, and send the summary on.')
    ff_can_submit_demand = fields.Boolean(
        string='Sends Demand to Distributor', compute='_compute_ff_can_submit_demand',
        help='What the employee setting and the company setting work out to.')

    @api.depends('ff_demand_submit')
    def _compute_ff_can_submit_demand(self):
        default = self.env['ir.config_parameter'].sudo().get_param('ff_base.demand_submit') == 'True'
        for employee in self:
            employee.ff_can_submit_demand = {
                'yes': True, 'no': False,
            }.get(employee.ff_demand_submit, default)
