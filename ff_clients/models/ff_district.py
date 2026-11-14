from odoo import api, fields, models


class FfDistrict(models.Model):
    _name = 'ff.district'
    _description = 'District / Territory'
    _order = 'name'

    name = fields.Char(required=True)
    code = fields.Char(required=True)
    team_id = fields.Many2one('ff.team', string='Region', required=True, ondelete='restrict', index=True)
    state_id = fields.Many2one('res.country.state', string='State', required=True, index=True)
    country_id = fields.Many2one(related='state_id.country_id', store=True, string='Country')
    active = fields.Boolean(default=True)
    api_created = fields.Boolean(string='Created from PIN code', readonly=True, copy=False,
                                 help='Made automatically from a PIN code lookup: to be checked by the office.')

    _name_state_uniq = models.Constraint('UNIQUE(name, state_id)', 'This district / territory already exists in the state.')

    @api.model
    def _register_hook(self):
        super()._register_hook()
        cr = self.env.cr
        cr.execute("ALTER TABLE ff_district ADD COLUMN IF NOT EXISTS team_id INTEGER;")

    @api.depends('name', 'state_id.code')
    def _compute_display_name(self):
        for district in self:
            district.display_name = '%s (%s)' % (district.name, district.state_id.code) if district.state_id else district.name
