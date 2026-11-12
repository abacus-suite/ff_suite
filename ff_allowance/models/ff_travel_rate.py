from odoo import api, fields, models


class FfTravelRate(models.Model):
    """What a kilometre is worth: on the route assigned to the employee, and on any other route.

    Set for one employee, or for a designation; an employee's own line wins over the designation's.
    """
    _name = 'ff.travel.rate'
    _description = 'Travel Rate per Km'
    _order = 'scope, id'

    scope = fields.Selection([('all', 'All field staff'), ('designation', 'Designation'), ('employee', 'Employee')],
                             required=True, default='designation')
    designation_id = fields.Many2one('ff.designation', string='Designation')
    employee_id = fields.Many2one('hr.employee', string='Employee')
    assigned_rate = fields.Monetary(string='Assigned Beat (per km)', required=True)
    other_rate = fields.Monetary(string='Other Beat (per km)', required=True,
                                 help='A route that is not assigned: given by the manager or through contact access.')
    company_id = fields.Many2one('res.company', required=True, default=lambda self: self.env.company)
    currency_id = fields.Many2one(related='company_id.currency_id')
    active = fields.Boolean(default=True)

    @api.model
    def _ff_for_employee(self, employee):
        employee = employee.sudo()
        rate = self.sudo().search([('scope', '=', 'employee'), ('employee_id', '=', employee.id)], limit=1)
        if not rate and employee.ff_designation_id:
            rate = self.sudo().search([('scope', '=', 'designation'),
                                       ('designation_id', '=', employee.ff_designation_id.id)], limit=1)
        if not rate:
            # The rate for all field staff, when nothing is set for the person or the designation.
            rate = self.sudo().search([('scope', '=', 'all')], limit=1)
        return (rate.assigned_rate, rate.other_rate) if rate else (0.0, 0.0)
