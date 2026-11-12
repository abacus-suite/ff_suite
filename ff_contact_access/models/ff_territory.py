from odoo import api, fields, models


class FfTerritory(models.Model):
    """A patch of a city that groups beats: City -> Territory -> Beat."""
    _name = 'ff.territory'
    _description = 'City / Town'
    _order = 'name'

    name = fields.Char(required=True)
    code = fields.Char()
    district_id = fields.Many2one('ff.district', string='District / Territory', index=True)
    team_id = fields.Many2one(related='district_id.team_id', string='Region', store=True, readonly=True)
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

    @api.model
    def _register_hook(self):
        super()._register_hook()
        cr = self.env.cr
        cr.execute("ALTER TABLE ff_territory ADD COLUMN IF NOT EXISTS team_id INTEGER;")
        cr.execute("""
            UPDATE ff_territory t
            SET team_id = d.team_id
            FROM ff_district d
            WHERE t.district_id = d.id AND t.team_id IS NULL AND d.team_id IS NOT NULL;
        """)
        cr.execute("""
            UPDATE ir_ui_menu m
            SET sequence = data.seq
            FROM (
                VALUES 
                    ('ff_base', 'menu_ff_teams', 10),
                    ('ff_clients', 'menu_ff_districts', 20),
                    ('ff_contact_access', 'menu_ff_territories', 30),
                    ('ff_contact_access', 'menu_ff_areas', 40),
                    ('ff_beat', 'menu_ff_beats', 50)
            ) AS data(module, name, seq)
            JOIN ir_model_data d ON d.module = data.module AND d.name = data.name AND d.model = 'ir.ui.menu'
            WHERE m.id = d.res_id;
        """)

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

    territory_id = fields.Many2one('ff.territory', string='City / Town', index=True,
                                   domain="[('district_id', '=?', district_id)]")

    @api.onchange('territory_id')
    def _onchange_territory_id(self):
        if self.territory_id.district_id:
            self.district_id = self.territory_id.district_id


class HrEmployee(models.Model):
    _inherit = 'hr.employee'

    ff_territory_ids = fields.Many2many('ff.territory', 'ff_employee_territory_rel', 'employee_id', 'territory_id',
                                        string='Cities / Towns', compute='_compute_ff_territory_ids', store=True,
                                        readonly=False,
                                        help='Fetched from the primary and secondary Districts / Territories: the '
                                             'cities / towns inside them.')
    ff_district_ids = fields.Many2many('ff.district', 'ff_employee_district_rel', 'employee_id', 'district_id',
                                       string='Primary Districts / Territories',
                                       help='The District / Territory master this person works in: the app shows these as '
                                            'their primary Territories.')
    ff_secondary_district_ids = fields.Many2many(
        'ff.district', 'ff_employee_secondary_district_rel', 'employee_id', 'district_id',
        string='Secondary Districts / Territories',
        help='Districts / Territories the employee also works in, besides the primary ones.')

    @api.depends('ff_district_ids', 'ff_secondary_district_ids')
    def _compute_ff_territory_ids(self):
        Territory = self.env['ff.territory'].sudo()
        for employee in self:
            districts = employee.ff_district_ids | employee.ff_secondary_district_ids
            if districts:
                employee.ff_territory_ids = Territory.search([('district_id', 'in', districts.ids)])
            else:
                # No district chosen: whatever was set before stays.
                employee.ff_territory_ids = employee._origin.ff_territory_ids

    def _ff_has_company_location(self):
        """True if any primary or secondary territory mapped to this employee has Company Location enabled."""
        for employee in self:
            territories = employee.ff_territory_ids
            if any(territories.mapped('is_company_location')):
                return True
        return False

    def _ff_territory_beats(self):
        """The beats of the primary and secondary territories."""
        territories = self.ff_territory_ids
        return self.env['ff.beat'].sudo().search([('territory_id', 'in', territories.ids)]) \
            if territories else self.env['ff.beat']

    def _ff_assign_territory_beats(self):
        """Put the beats of the territories on the employee's assigned beats (never taking any away)."""
        for employee in self:
            beats = employee._ff_territory_beats() - employee.ff_route_ids
            if beats:
                employee.sudo().write({'ff_route_ids': [(4, b.id) for b in beats]})

    @api.onchange('ff_territory_ids')
    def _onchange_territory_beats(self):
        beats = self._ff_territory_beats()
        if beats:
            self.ff_route_ids = self.ff_route_ids | beats

    @api.model_create_multi
    def create(self, vals_list):
        employees = super().create(vals_list)
        employees.filtered('ff_territory_ids')._ff_assign_territory_beats()
        return employees

    def write(self, vals):
        result = super().write(vals)
        if {'ff_territory_ids', 'ff_district_ids', 'ff_secondary_district_ids'} & set(vals):
            self._ff_assign_territory_beats()
        return result
