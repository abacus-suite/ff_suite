from odoo import api, fields, models
from odoo.exceptions import ValidationError

from odoo.addons.ff_base.tools import haversine_m


class FfBeat(models.Model):
    """A route of clients (called Beat, Patch... depending on the route type)."""
    _name = 'ff.beat'
    _description = 'Route (Beat / Patch)'
    _inherit = ['mail.thread']
    _order = 'name'

    name = fields.Char(required=True, tracking=True)
    code = fields.Char()
    route_type_id = fields.Many2one('ff.route.type', string='Route Type', index=True, tracking=True)
    team_id = fields.Many2one('ff.team', string='Team', tracking=True)
    country_id = fields.Many2one('res.country', string='Country')
    state_id = fields.Many2one('res.country.state', string='State', domain="[('country_id', '=?', country_id)]")
    district_id = fields.Many2one('ff.district', string='City / District', index=True,
                                  domain="[('state_id', '=?', state_id)]")
    line_ids = fields.One2many('ff.beat.line', 'beat_id', string='Clients', copy=True)
    employee_ids = fields.Many2many('hr.employee', 'ff_beat_employee_rel', 'beat_id', 'employee_id',
                                    string='Assigned Employees')
    client_count = fields.Integer(compute='_compute_route', store=True)
    planned_km = fields.Float(string='Route Length (km)', digits=(10, 1), compute='_compute_route', store=True,
                              help='Straight-line distance through the clients in order.')
    allowance_km = fields.Float(string='Allowance km per Day', digits=(10, 1),
                                help='Fixed km paid for a day worked on this route (route-based allowance policies).')
    company_id = fields.Many2one('res.company', required=True, default=lambda self: self.env.company)
    active = fields.Boolean(default=True)

    @api.constrains('route_type_id')
    def _check_route_type(self):
        for beat in self:
            if not beat.route_type_id:
                raise ValidationError(self.env._('Route "%s" needs a route type.', beat.name))

    @api.onchange('district_id')
    def _onchange_district_id(self):
        if self.district_id:
            self.state_id = self.district_id.state_id
            self.country_id = self.district_id.country_id

    @api.onchange('state_id')
    def _onchange_state_id(self):
        if self.state_id:
            self.country_id = self.state_id.country_id

    @api.depends('line_ids.sequence', 'line_ids.partner_id.partner_latitude', 'line_ids.partner_id.partner_longitude')
    def _compute_route(self):
        for beat in self:
            partners = beat.line_ids.sorted('sequence').partner_id
            beat.client_count = len(partners)
            located = [(p.partner_latitude, p.partner_longitude) for p in partners
                       if p.partner_latitude or p.partner_longitude]
            beat.planned_km = sum(
                haversine_m(*located[i], *located[i + 1]) for i in range(len(located) - 1)) / 1000.0

    @api.depends('name', 'route_type_id.name')
    def _compute_display_name(self):
        for beat in self:
            beat.display_name = '%s: %s' % (beat.route_type_id.name, beat.name) if beat.route_type_id else beat.name


class FfBeatLine(models.Model):
    _name = 'ff.beat.line'
    _description = 'Route Client'
    _order = 'sequence, id'

    beat_id = fields.Many2one('ff.beat', required=True, index=True, ondelete='cascade')
    sequence = fields.Integer(default=10)
    partner_id = fields.Many2one('res.partner', string='Client', required=True,
                                 domain=[('ff_is_client', '=', True)])
    partner_category_id = fields.Many2one(related='partner_id.ff_category_id', string='Category')
    partner_city = fields.Char(related='partner_id.city', string='City')
    partner_phone = fields.Char(related='partner_id.phone', string='Phone')

    _beat_partner_uniq = models.Constraint('UNIQUE(beat_id, partner_id)', 'A client appears only once per route.')
