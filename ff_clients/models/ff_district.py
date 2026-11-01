from odoo import api, fields, models


class FfDistrict(models.Model):
    _name = 'ff.district'
    _description = 'City / District'
    _order = 'country_id, state_id, name'

    name = fields.Char(required=True)
    code = fields.Char()
    state_id = fields.Many2one('res.country.state', string='State', required=True, index=True)
    country_id = fields.Many2one(related='state_id.country_id', store=True, string='Country')
    active = fields.Boolean(default=True)

    _name_state_uniq = models.Constraint('UNIQUE(name, state_id)', 'This city / district already exists in the state.')

    @api.depends('name', 'state_id.code')
    def _compute_display_name(self):
        for district in self:
            district.display_name = '%s (%s)' % (district.name, district.state_id.code) if district.state_id else district.name
