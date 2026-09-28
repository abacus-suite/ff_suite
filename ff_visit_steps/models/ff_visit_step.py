from odoo import api, fields, models
from odoo.exceptions import ValidationError

STEP_TYPES = [
    ('note', 'Visit notes'),
    ('photo', 'Photo'),
    ('form', 'Form'),
    ('stock', 'Stock count'),
    ('order', 'Take order'),
    ('payment', 'Payment collection'),
    ('confirm', 'Confirmation'),
]


class FfVisitStep(models.Model):
    """Step 1, step 2... of a visit, configured per department and contact category."""
    _name = 'ff.visit.step'
    _description = 'Visit Step'
    _order = 'sequence, id'

    name = fields.Char(required=True, translate=True)
    sequence = fields.Integer(default=10)
    step_type = fields.Selection(STEP_TYPES, string='Type', required=True, default='note')
    form_id = fields.Many2one('ff.form', string='Form', help='The form to fill in this step.')
    department_ids = fields.Many2many('hr.department', string='Departments', help='Leave empty for every department.')
    category_ids = fields.Many2many('ff.contact.category', string='Contact Categories',
                                    help='Leave empty for every contact category.')
    mandatory = fields.Boolean(help='The visit cannot be checked out before this step is done.')
    allow_skip = fields.Boolean(string='Can Be Skipped', default=True,
                                help='Field staff may skip the step and give a reason.')
    skip_reason_required = fields.Boolean(string='Reason Needed to Skip', default=True)
    help_text = fields.Char(string='Instruction', translate=True)
    company_id = fields.Many2one('res.company', required=True, default=lambda self: self.env.company)
    active = fields.Boolean(default=True)

    _name_company_uniq = models.Constraint('UNIQUE(name, company_id)', 'This visit step already exists.')

    @api.constrains('step_type', 'form_id')
    def _check_form(self):
        for step in self:
            if step.step_type == 'form' and not step.form_id:
                raise ValidationError(self.env._('Step "%s" needs a form.', step.name))

    @api.constrains('mandatory', 'allow_skip')
    def _check_skip(self):
        for step in self:
            if step.mandatory and step.allow_skip and not step.skip_reason_required:
                raise ValidationError(self.env._(
                    'A mandatory step that can be skipped must ask for a reason ("%s").', step.name))

    @api.model
    def ff_for(self, employee, partner=None):
        """Steps that apply to this employee (and this contact's category)."""
        employee = employee.sudo()
        steps = self.sudo().search([
            ('company_id', 'in', employee.company_id.ids),
            '|', ('department_ids', '=', False), ('department_ids', 'in', employee.department_id.ids),
        ])
        if partner is not None:
            category = partner.ff_category_id
            steps = steps.filtered(lambda s: not s.category_ids or category in s.category_ids)
        return steps
