from odoo import api, fields, models


class ResPartner(models.Model):
    _inherit = 'res.partner'

    ff_beat_line_ids = fields.One2many('ff.beat.line', 'partner_id', string='Route Lines')
    ff_route_ids = fields.Many2many('ff.beat', string='Routes', compute='_compute_ff_route_ids',
                                    inverse='_inverse_ff_route_ids', search='_search_ff_route_ids',
                                    help="Routes this contact belongs to. Adding a route assigns the route's employees.")

    @api.depends('ff_beat_line_ids.beat_id')
    def _compute_ff_route_ids(self):
        for partner in self:
            partner.ff_route_ids = partner.ff_beat_line_ids.beat_id

    def _inverse_ff_route_ids(self):
        Line = self.env['ff.beat.line'].sudo()
        for partner in self:
            current = partner.ff_beat_line_ids.beat_id
            for route in partner.ff_route_ids - current:
                Line.create({
                    'beat_id': route.id,
                    'partner_id': partner.id,
                    'sequence': max(route.sudo().line_ids.mapped('sequence') or [0]) + 10,
                })
            partner.sudo().ff_beat_line_ids.filtered(lambda l: l.beat_id not in partner.ff_route_ids).unlink()

    def _search_ff_route_ids(self, operator, value):
        return [('ff_beat_line_ids.beat_id', operator, value)]

    @api.onchange('ff_route_ids')
    def _onchange_ff_route_ids(self):
        missing = self.ff_route_ids.employee_ids - self.ff_employee_ids
        if missing:
            self.ff_employee_ids |= missing

    @api.model
    def _ff_ownership_domain(self, employee):
        """Also the contacts of the routes worked by the employee (or their team),
        even when nobody was assigned to those contacts yet."""
        domain = super()._ff_ownership_domain(employee)
        routes = employee._ff_scope_employees().ff_route_ids
        if not routes:
            return domain
        return ['|'] + domain + [('ff_beat_line_ids.beat_id', 'in', routes.ids)]
