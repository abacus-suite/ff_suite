from odoo import api, fields, models


class FfDistrict(models.Model):
    _name = 'ff.district'
    _description = 'City / District'
    _order = 'name'

    name = fields.Char(required=True)
    code = fields.Char()
    team_id = fields.Many2one('ff.team', string='Region', ondelete='set null', index=True)
    state_id = fields.Many2one('res.country.state', string='State', required=True, index=True)
    country_id = fields.Many2one(related='state_id.country_id', store=True, string='Country')
    active = fields.Boolean(default=True)

    _name_state_uniq = models.Constraint('UNIQUE(name, state_id)', 'This city / district already exists in the state.')

    @api.model
    def _register_hook(self):
        super()._register_hook()
        cr = self.env.cr
        cr.execute("ALTER TABLE ff_district ADD COLUMN IF NOT EXISTS team_id INTEGER;")

    @api.depends('name', 'state_id.code')
    def _compute_display_name(self):
        for district in self:
            district.display_name = '%s (%s)' % (district.name, district.state_id.code) if district.state_id else district.name
