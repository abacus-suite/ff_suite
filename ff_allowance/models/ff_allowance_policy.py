from odoo import api, fields, models

BASES = [
    ('gps', 'GPS tracked distance'),
    ('client', 'Client-to-client distance'),
    ('route', 'Route-to-route distance'),
    ('fixed', 'Fixed amount per working day'),
]
VEHICLES = [
    ('two_wheeler', 'Two-wheeler'),
    ('four_wheeler', 'Four-wheeler'),
    ('public', 'Public transport'),
    ('other', 'Other'),
]


class FfAllowancePolicy(models.Model):
    _name = 'ff.allowance.policy'
    _description = 'Travel Allowance Policy'
    _inherit = ['mail.thread']
    _order = 'sequence, name'

    name = fields.Char(required=True, tracking=True)
    sequence = fields.Integer(default=10)
    basis = fields.Selection(BASES, string='Distance Basis', required=True, default='gps', tracking=True,
                             help='GPS: actual tracked km.\n'
                                  'Client-to-client: punch-in -> each visited client -> punch-out (straight line x road factor).\n'
                                  'Route-to-route: fixed km per route worked + agreed km between routes.\n'
                                  'Fixed: a fixed amount for each working day.')
    vehicle_type = fields.Selection(VEHICLES, default='two_wheeler')
    company_id = fields.Many2one('res.company', required=True, default=lambda self: self.env.company)
    currency_id = fields.Many2one(related='company_id.currency_id')
    rate_per_km = fields.Monetary(string='Rate per km', tracking=True)
    fixed_amount = fields.Monetary(string='Fixed Amount per Day', tracking=True)
    road_factor = fields.Float(default=1.3, digits=(4, 2),
                               help='Multiplier from straight-line distance to road distance (client and estimated legs).')
    max_km_per_day = fields.Float(string='Max km per Day', help='0 = no limit.')
    department_ids = fields.Many2many('hr.department', string='Departments',
                                      help='Applies to employees of these departments.')
    employee_ids = fields.Many2many('hr.employee', string='Employees',
                                    help='Applies to these employees (overrides departments).')
    active = fields.Boolean(default=True)

    @api.model
    def _ff_for_employee(self, employee):
        """Policy of an employee: explicit on the employee, then listed employees,
        then department, then a company-wide default (no departments/employees)."""
        employee = employee.sudo()
        if employee.ff_allowance_policy_id:
            return employee.ff_allowance_policy_id
        policies = self.sudo().search([('company_id', '=', employee.company_id.id)])
        for match in (
            policies.filtered(lambda p: employee in p.employee_ids),
            policies.filtered(lambda p: employee.department_id and employee.department_id in p.department_ids),
            policies.filtered(lambda p: not p.department_ids and not p.employee_ids),
        ):
            if match:
                return match[0]
        return self.browse()
