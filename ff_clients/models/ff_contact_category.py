from odoo import api, fields, models

CATEGORY_TYPES = [
    ('lead', 'Lead / Prospect'),
    ('customer', 'Customer'),
    ('outlet', 'Outlet / Retailer'),
    ('distributor', 'Distributor / Dealer'),
    ('other', 'Other'),
]


class FfContactCategory(models.Model):
    _name = 'ff.contact.category'
    _description = 'Field Contact Category'
    _order = 'sequence, name'

    name = fields.Char(required=True, translate=True)
    code = fields.Char()
    category_type = fields.Selection(CATEGORY_TYPES, string='Type', required=True, default='customer')
    department_ids = fields.Many2many(
        'hr.department', string='Departments',
        help='Only employees of these departments see contacts of this category. Leave empty for everyone.')
    allow_orders = fields.Boolean(string='Orders Allowed', compute='_compute_allow_orders', store=True,
                                  readonly=False, help='Field staff can take orders for contacts of this category.')
    requires_approval = fields.Boolean(string='New Contacts Need Approval', default=True,
                                       help='Contacts added from the app by officers wait for manager approval.')
    sequence = fields.Integer(default=10)
    color = fields.Integer()
    partner_count = fields.Integer(string='Contacts', compute='_compute_partner_count')
    company_id = fields.Many2one('res.company', required=True, default=lambda self: self.env.company)
    active = fields.Boolean(default=True)

    _name_company_uniq = models.Constraint('UNIQUE(name, company_id)', 'This contact category already exists.')

    @api.depends('category_type')
    def _compute_allow_orders(self):
        for category in self:
            category.allow_orders = category.category_type != 'lead'

    def _compute_partner_count(self):
        counts = dict(self.env['res.partner']._read_group(
            [('ff_category_id', 'in', self.ids)], ['ff_category_id'], ['__count']))
        for category in self:
            category.partner_count = counts.get(category, 0)

    @api.model
    def ff_for_employee(self, employee):
        """Categories visible to ``employee`` through their department."""
        employee = employee.sudo()
        return self.sudo().search([
            ('company_id', 'in', employee.company_id.ids),
            '|', ('department_ids', '=', False), ('department_ids', 'in', employee.department_id.ids),
        ])

    def action_view_contacts(self):
        self.ensure_one()
        action = self.env['ir.actions.act_window']._for_xml_id('ff_clients.ff_client_action')
        action['domain'] = [('ff_category_id', '=', self.id)]
        action['context'] = {'default_ff_is_client': True, 'default_ff_category_id': self.id}
        return action
