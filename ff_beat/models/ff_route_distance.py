from odoo import api, fields, models
from odoo.exceptions import ValidationError


class FfRouteDistance(models.Model):
    """Agreed travel distance between two routes (used by route-based allowances)."""
    _name = 'ff.route.distance'
    _description = 'Route to Route Distance'
    _order = 'from_beat_id, to_beat_id'

    from_beat_id = fields.Many2one('ff.beat', string='From Route', required=True, index=True, ondelete='cascade')
    to_beat_id = fields.Many2one('ff.beat', string='To Route', required=True, index=True, ondelete='cascade')
    distance_km = fields.Float(string='Distance (km)', digits=(10, 1), required=True)

    _pair_uniq = models.Constraint('UNIQUE(from_beat_id, to_beat_id)', 'This route pair already has a distance.')

    @api.constrains('from_beat_id', 'to_beat_id')
    def _check_pair(self):
        for rec in self:
            if rec.from_beat_id == rec.to_beat_id:
                raise ValidationError(self.env._('Choose two different routes.'))

    @api.model
    def ff_lookup(self, beat_a, beat_b):
        """Distance in km between two routes (either direction), or None."""
        rec = self.sudo().search([
            '|', '&', ('from_beat_id', '=', beat_a.id), ('to_beat_id', '=', beat_b.id),
            '&', ('from_beat_id', '=', beat_b.id), ('to_beat_id', '=', beat_a.id),
        ], limit=1)
        return rec.distance_km if rec else None
