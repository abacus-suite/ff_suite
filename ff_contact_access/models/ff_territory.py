from odoo import api, fields, models


class FfTerritory(models.Model):
    """A patch of a city that groups beats: City -> Territory -> Beat."""
    _name = 'ff.territory'
    _description = 'Territory'
    _order = 'name'

    name = fields.Char(required=True)
    code = fields.Char()
    district_id = fields.Many2one('ff.district', string='City / District', index=True)
    beat_ids = fields.One2many('ff.beat', 'territory_id', string='Beats')
    beat_count = fields.Integer(compute='_compute_beat_count')
    active = fields.Boolean(default=True)

    @api.depends('beat_ids')
    def _compute_beat_count(self):
        for territory in self:
            territory.beat_count = len(territory.beat_ids)


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
    ff_district_ids = fields.Many2many('ff.district', 'ff_employee_district_rel', 'employee_id', 'district_id',
                                       string='Cities')
