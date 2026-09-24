from odoo import api, fields, models


class FfVisitOutcome(models.Model):
    """Configurable visit results, per department and contact category."""
    _name = 'ff.visit.outcome'
    _description = 'Visit Outcome'
    _order = 'sequence, id'

    name = fields.Char(required=True, translate=True)
    code = fields.Char(index=True, help='Technical code used by older app versions.')
    sequence = fields.Integer(default=10)
    department_ids = fields.Many2many('hr.department', string='Departments',
                                      help='Leave empty for every department.')
    category_ids = fields.Many2many('ff.contact.category', string='Contact Categories',
                                    help='Leave empty for every contact category.')
    productive = fields.Boolean(default=True, help='Counts as a productive visit in reports.')
    is_order = fields.Boolean(string='Set When an Order Is Taken',
                              help='Used automatically when an order is placed during the visit.')
    requires_note = fields.Boolean(string='Note Required')
    requires_photo = fields.Boolean(string='Photo Required')
    company_id = fields.Many2one('res.company', required=True, default=lambda self: self.env.company)
    active = fields.Boolean(default=True)

    @api.model
    def ff_for(self, employee, partner):
        """Outcomes available to ``employee`` when visiting ``partner``."""
        employee = employee.sudo()
        outcomes = self.sudo().search([
            ('company_id', 'in', employee.company_id.ids),
            '|', ('department_ids', '=', False), ('department_ids', 'in', employee.department_id.ids),
        ])
        category = partner.ff_category_id
        return outcomes.filtered(lambda o: not o.category_ids or category in o.category_ids)
