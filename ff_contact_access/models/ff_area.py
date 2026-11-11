from odoo import api, fields, models


class FfArea(models.Model):
    """A neighbourhood inside a territory: City -> Territory -> Area. Contacts are placed in an area."""
    _name = 'ff.area'
    _description = 'Area'
    _order = 'name'

    name = fields.Char(required=True)
    code = fields.Char(readonly=True, copy=False, default='New',
                       help='Generated automatically when the area is created.')
    territory_id = fields.Many2one('ff.territory', string='City / Town', required=True, index=True, ondelete='cascade')
    district_id = fields.Many2one(related='territory_id.district_id', string='District / Territory', store=True, index=True)
    active = fields.Boolean(default=True)
    contact_count = fields.Integer(compute='_compute_contact_count')

    _name_territory_uniq = models.Constraint(
        'UNIQUE(name, territory_id)', 'This area already exists in the territory.')

    @api.model_create_multi
    def create(self, vals_list):
        for vals in vals_list:
            if not vals.get('code') or vals['code'] == 'New':
                vals['code'] = self.env['ir.sequence'].next_by_code('ff.area') or 'New'
        return super().create(vals_list)

    def _compute_contact_count(self):
        counts = {group.id: n for group, n in self.env['res.partner']._read_group(
            [('ff_area_id', 'in', self.ids)], ['ff_area_id'], ['__count'])}
        for area in self:
            area.contact_count = counts.get(area.id, 0)

    def action_view_contacts(self):
        self.ensure_one()
        return {
            'name': self.env._('Contacts'),
            'type': 'ir.actions.act_window',
            'res_model': 'res.partner',
            'view_mode': 'list,form',
            'domain': [('ff_area_id', '=', self.id)],
            'context': {'default_ff_area_id': self.id},
        }
