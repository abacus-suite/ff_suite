from odoo import fields, models


class FfBeat(models.Model):
    """A route usually belongs to one distributor's territory."""
    _inherit = 'ff.beat'

    ff_distributor_id = fields.Many2one('res.partner', string='Distributor',
                                        domain=[('ff_is_distributor', '=', True)],
                                        help='Suggested for every outlet on this route.')
