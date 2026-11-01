from odoo import api, fields, models


class FfRouteType(models.Model):
    """What a department calls its routes: Beat, Patch, Route, Territory..."""
    _name = 'ff.route.type'
    _description = 'Route Type'
    _order = 'sequence, name'

    name = fields.Char(required=True, translate=True, help='Shown in the app, e.g. "Beat" or "Patch".')
    department_ids = fields.Many2many('hr.department', string='Departments',
                                      help='Departments that use this name. Leave empty for everyone.')
    sequence = fields.Integer(default=10)
    route_count = fields.Integer(string='Routes', compute='_compute_route_count')
    company_id = fields.Many2one('res.company', required=True, default=lambda self: self.env.company)
    active = fields.Boolean(default=True)

    def _compute_route_count(self):
        counts = dict(self.env['ff.beat']._read_group([('route_type_id', 'in', self.ids)], ['route_type_id'], ['__count']))
        for route_type in self:
            route_type.route_count = counts.get(route_type, 0)

    @api.model
    def ff_for_employee(self, employee):
        """Route types usable by ``employee``: department-specific ones first."""
        employee = employee.sudo()
        types = self.sudo().search([
            ('company_id', 'in', employee.company_id.ids),
            '|', ('department_ids', '=', False), ('department_ids', 'in', employee.department_id.ids),
        ])
        specific = types.filtered(lambda t: t.department_ids)
        return specific + (types - specific)
