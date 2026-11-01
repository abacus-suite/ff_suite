from odoo import api, fields, models


class FfBeat(models.Model):
    """A route usually belongs to one distributor's territory."""
    _inherit = 'ff.beat'

    ff_distributor_id = fields.Many2one('res.partner', string='Distributor',
                                        domain=[('ff_is_distributor', '=', True)],
                                        help='Suggested for every outlet on this route.')

    @api.onchange('ff_distributor_id')
    def _onchange_ff_distributor_id(self):
        if self.ff_distributor_id:
            self._ff_sync_beat_to_distributor(self.ff_distributor_id)

    def _ff_sync_beat_to_distributor(self, distributor=None):
        for beat in self:
            dist = distributor or beat.ff_distributor_id
            if not dist:
                continue
            vals = {}
            if beat.territory_id:
                if not dist.ff_territory_id:
                    vals['ff_territory_id'] = beat.territory_id.id
                elif beat.territory_id != dist.ff_territory_id and 'ff_secondary_territory_ids' in dist._fields:
                    if beat.territory_id not in dist.ff_secondary_territory_ids:
                        vals['ff_secondary_territory_ids'] = [(4, beat.territory_id.id)]

            district = beat.district_id or (beat.territory_id.district_id if beat.territory_id else False)
            if district:
                if not dist.ff_district_id:
                    vals['ff_district_id'] = district.id
                elif district != dist.ff_district_id and 'ff_secondary_district_ids' in dist._fields:
                    if district not in dist.ff_secondary_district_ids:
                        vals['ff_secondary_district_ids'] = [(4, district.id)]

            if vals:
                dist.sudo().write(vals)

    @api.model_create_multi
    def create(self, vals_list):
        beats = super().create(vals_list)
        for beat in beats:
            if beat.ff_distributor_id:
                beat._ff_sync_beat_to_distributor()
        return beats

    def write(self, vals):
        res = super().write(vals)
        if any(f in vals for f in ('ff_distributor_id', 'territory_id', 'district_id')):
            for beat in self:
                if beat.ff_distributor_id:
                    beat._ff_sync_beat_to_distributor()
        return res
