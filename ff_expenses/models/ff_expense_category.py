from odoo import api, fields, models


class FfExpenseCategory(models.Model):
    """Expense types field staff can claim, configurable per department."""
    _name = 'ff.expense.category'
    _description = 'Field Expense Type'
    _order = 'sequence, name'

    name = fields.Char(required=True, translate=True)
    code = fields.Char()
    sequence = fields.Integer(default=10)
    department_ids = fields.Many2many('hr.department', string='Departments',
                                      help='Leave empty for every department.')
    requires_receipt = fields.Boolean(string='Receipt Required', default=True)
    requires_client = fields.Boolean(string='Contact Required',
                                     help='The claim must be linked to a contact (e.g. client entertainment).')
    max_amount = fields.Monetary(string='Maximum per Claim', help='0 = no limit.')
    company_id = fields.Many2one('res.company', required=True, default=lambda self: self.env.company)
    currency_id = fields.Many2one(related='company_id.currency_id')
    active = fields.Boolean(default=True)

    _name_company_uniq = models.Constraint('UNIQUE(name, company_id)', 'This expense type already exists.')

    @api.model
    def ff_for_employee(self, employee):
        employee = employee.sudo()
        return self.sudo().search([
            ('company_id', 'in', employee.company_id.ids),
            '|', ('department_ids', '=', False), ('department_ids', 'in', employee.department_id.ids),
        ])
