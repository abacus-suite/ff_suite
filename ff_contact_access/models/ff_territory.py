from odoo import api, fields, models


class FfTerritory(models.Model):
    """A patch of a city that groups beats: City -> Territory -> Beat."""
    _name = 'ff.territory'
    _description = 'Territory'
    _order = 'name'

    name = fields.Char(required=True)
    code = fields.Char()
    district_id = fields.Many2one('ff.district', string='City / District', index=True)
    state_id = fields.Many2one(related='district_id.state_id', string='State', store=True, readonly=True)
    country_id = fields.Many2one(related='district_id.country_id', string='Country', store=True, readonly=True)
    beat_ids = fields.One2many('ff.beat', 'territory_id', string='Beats')
    beat_count = fields.Integer(compute='_compute_beat_count')
    employee_ids = fields.Many2many(
        'hr.employee', 'ff_employee_territory_rel', 'territory_id', 'employee_id',
        string='Primary Employees', readonly=True)
    secondary_employee_ids = fields.Many2many(
        'hr.employee', 'ff_employee_secondary_territory_rel', 'territory_id', 'employee_id',
        string='Secondary Employees', readonly=True)
    active = fields.Boolean(default=True)
    is_company_location = fields.Boolean(
        string='Company Location', default=False,
        help='When enabled, employees mapped to this territory can collect samples directly from Company stock in the app.')
    ff_price_category = fields.Selection(
        [('149', '149'), ('179', '179')], string='Price Category',
        help='The MRP category of the outlets in this territory (149 or 179). A new PO for one of these outlets '
             'shows only the products of this category.')
    company_location = fields.Boolean(string='Company Location', related='is_company_location',
                                      readonly=False, store=True)
    ff_is_company_location = fields.Boolean(string='Company Location', related='is_company_location',
                                            readonly=False, store=True)

    @api.depends('beat_ids')
    def _compute_beat_count(self):
        for territory in self:
            territory.beat_count = len(territory.beat_ids)

    def action_view_beats(self):
        self.ensure_one()
        return {
            'name': 'Beats',
            'type': 'ir.actions.act_window',
            'res_model': 'ff.beat',
            'view_mode': 'list,form',
            'domain': [('territory_id', '=', self.id)],
            'context': {
                'default_territory_id': self.id,
                'default_district_id': self.district_id.id if self.district_id else False,
            },
        }


class FfBeat(models.Model):
    _inherit = 'ff.beat'

    territory_id = fields.Many2one('ff.territory', string='Territory', index=True,
                                   domain="[('district_id', '=?', district_id)]")

    @api.onchange('territory_id')
    def _onchange_territory_id(self):
        if self.territory_id.district_id:
            self.district_id = self.territory_id.district_id


class HrEmployee(models.Model):
    _inherit = 'hr.employee'

    ff_territory_ids = fields.Many2many('ff.territory', 'ff_employee_territory_rel', 'employee_id', 'territory_id',
                                        string='Territories')
    ff_secondary_territory = fields.Many2many(
        'ff.territory', 'ff_employee_secondary_territory_rel', 'employee_id', 'territory_id',
        string='Secondary Territories',
        help='Territories the employee also works in, besides the primary ones above.')
    ff_district_ids = fields.Many2many('ff.district', 'ff_employee_district_rel', 'employee_id', 'district_id',
                                       string='Cities')

    def _ff_has_company_location(self):
        """True if any primary or secondary territory mapped to this employee has Company Location enabled."""
        for employee in self:
            territories = employee.ff_territory_ids | employee.ff_secondary_territory
            if any(territories.mapped('is_company_location')):
                return True
        return False

    def _ff_territory_beats(self):
        """The beats of the primary and secondary territories."""
        territories = self.ff_territory_ids | self.ff_secondary_territory
        return self.env['ff.beat'].sudo().search([('territory_id', 'in', territories.ids)]) \
            if territories else self.env['ff.beat']

    def _ff_assign_territory_beats(self):
        """Put the beats of the territories on the employee's assigned beats (never taking any away)."""
        for employee in self:
            beats = employee._ff_territory_beats() - employee.ff_route_ids
            if beats:
                employee.sudo().write({'ff_route_ids': [(4, b.id) for b in beats]})

    @api.onchange('ff_territory_ids', 'ff_secondary_territory')
    def _onchange_territory_beats(self):
        beats = self._ff_territory_beats()
        if beats:
            self.ff_route_ids = self.ff_route_ids | beats

    @api.model_create_multi
    def create(self, vals_list):
        employees = super().create(vals_list)
        employees.filtered(lambda e: e.ff_territory_ids or e.ff_secondary_territory)._ff_assign_territory_beats()
        return employees

    def write(self, vals):
        result = super().write(vals)
        if 'ff_territory_ids' in vals or 'ff_secondary_territory' in vals:
            self._ff_assign_territory_beats()
        return result
