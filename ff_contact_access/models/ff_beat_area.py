from odoo import api, fields, models


class FfBeatArea(models.Model):
    """The areas a beat covers (inside its territory), chosen in the app."""
    _inherit = 'ff.beat'

    ff_area_ids = fields.Many2many('ff.area', 'ff_beat_area_rel', 'beat_id', 'area_id', string='Areas',
                                   help='The areas of the District / Territory this beat covers (chosen in the app).')

    def _ff_set_areas(self, area_ids):
        """Only areas of the beat's own territory are kept. True when the list changed."""
        self.ensure_one()
        beat = self.sudo()
        areas = self.env['ff.area'].sudo().browse([int(a) for a in (area_ids or [])]).exists()
        # Only areas of the beat's District / Territory (the app's Territory) are kept.
        if beat.district_id:
            areas = areas.filtered(lambda a: a.district_id == beat.district_id)
        if set(areas.ids) == set(beat.ff_area_ids.ids):
            return False
        beat.write({'ff_area_ids': [(6, 0, areas.ids)]})
        return True

    def ff_app_payload(self):
        payload = super().ff_app_payload()
        payload['areas'] = [{'id': a.id, 'name': a.name} for a in self.sudo().ff_area_ids]
        payload['area_ids'] = self.sudo().ff_area_ids.ids
        return payload

    @api.model
    def ff_create_from_app(self, employee, data):
        beat = super().ff_create_from_app(employee, data)
        if data.get('area_ids'):
            beat._ff_set_areas(data['area_ids'])
        return beat

    @api.model
    def ff_update_from_app(self, employee, beat, data):
        beat = super().ff_update_from_app(employee, beat, data)
        if data.get('area_ids') is not None and beat._ff_set_areas(data['area_ids']):
            beat._ff_send_back_for_approval(employee)
        return beat
