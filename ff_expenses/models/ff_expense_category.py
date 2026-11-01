from odoo import api, fields, models


class FfExpenseCategory(models.Model):
    """Expense categories and their sub-categories, configurable per department.

    A category with no sub-categories is claimed on its own; one with
    sub-categories is claimed through one of them.
    """
    _name = 'ff.expense.category'
    _description = 'Field Expense Type'
    _order = 'sequence, name'

    name = fields.Char(required=True, translate=True)
    code = fields.Char()
    sequence = fields.Integer(default=10)
    parent_id = fields.Many2one('ff.expense.category', string='Category', index=True, ondelete='cascade',
                                domain=[('parent_id', '=', False)],
                                help='Set to make this a sub-category of that category.')
    child_ids = fields.One2many('ff.expense.category', 'parent_id', string='Sub-categories')
    department_ids = fields.Many2many('hr.department', string='Departments',
                                      help='Leave empty for every department.')
    requires_receipt = fields.Boolean(string='Receipt Required', default=True)
    requires_client = fields.Boolean(string='Contact Required',
                                     help='The claim must be linked to a contact (e.g. client entertainment).')
    max_amount = fields.Monetary(string='Maximum per Claim', help='0 = no limit.')
    company_id = fields.Many2one('res.company', required=True, default=lambda self: self.env.company)
    currency_id = fields.Many2one(related='company_id.currency_id')
    active = fields.Boolean(default=True)

    _name_parent_company_uniq = models.Constraint(
        'UNIQUE(name, parent_id, company_id)', 'This expense type already exists.')

    def _auto_init(self):
        # The old rule (one name per company) would stop "Food Expenses" sitting under
        # several categories, and Odoo does not drop a constraint that was renamed.
        self.env.cr.execute(
            'ALTER TABLE IF EXISTS ff_expense_category DROP CONSTRAINT IF EXISTS ff_expense_category_name_company_uniq')
        return super()._auto_init()

    @api.depends('name', 'parent_id.name')
    def _compute_display_name(self):
        for category in self:
            category.display_name = ('%s / %s' % (category.parent_id.name, category.name)
                                     if category.parent_id else category.name)

    @api.model
    def ff_for_employee(self, employee):
        """Top-level categories this person may use (their sub-categories hang off them)."""
        employee = employee.sudo()
        return self.sudo().search([
            ('company_id', 'in', employee.company_id.ids), ('parent_id', '=', False),
            '|', ('department_ids', '=', False), ('department_ids', 'in', employee.department_id.ids),
        ])


class FfExpenseCard(models.Model):
    """A company card an expense can be paid with."""
    _name = 'ff.expense.card'
    _description = 'Company Card'
    _order = 'sequence, name'

    name = fields.Char(required=True)
    sequence = fields.Integer(default=10)
    company_id = fields.Many2one('res.company', required=True, default=lambda self: self.env.company)
    active = fields.Boolean(default=True)
