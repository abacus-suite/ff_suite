from odoo import api, fields, models

from odoo.addons.ff_base.tools import haversine_m


class FfBeat(models.Model):
    _name = 'ff.beat'
    _description = 'Beat Route'
    _inherit = ['mail.thread']
    _order = 'name'

    name = fields.Char(required=True, tracking=True)
    code = fields.Char()
    team_id = fields.Many2one('ff.team', string='Team', tracking=True)
    line_ids = fields.One2many('ff.beat.line', 'beat_id', string='Clients', copy=True)
    client_count = fields.Integer(compute='_compute_route', store=True)
    planned_km = fields.Float(string='Route Length (km)', digits=(10, 1), compute='_compute_route', store=True,
                              help='Straight-line distance through the clients in order.')
    company_id = fields.Many2one('res.company', required=True, default=lambda self: self.env.company)
    active = fields.Boolean(default=True)

    @api.depends('line_ids.sequence', 'line_ids.partner_id.partner_latitude', 'line_ids.partner_id.partner_longitude')
    def _compute_route(self):
        for beat in self:
            partners = beat.line_ids.sorted('sequence').partner_id
            beat.client_count = len(partners)
            located = [(p.partner_latitude, p.partner_longitude) for p in partners
                       if p.partner_latitude or p.partner_longitude]
            beat.planned_km = sum(
                haversine_m(*located[i], *located[i + 1]) for i in range(len(located) - 1)) / 1000.0


class FfBeatLine(models.Model):
    _name = 'ff.beat.line'
    _description = 'Beat Route Client'
    _order = 'sequence, id'

    beat_id = fields.Many2one('ff.beat', required=True, index=True, ondelete='cascade')
    sequence = fields.Integer(default=10)
    partner_id = fields.Many2one('res.partner', string='Client', required=True,
                                 domain=[('ff_is_client', '=', True)])
    partner_city = fields.Char(related='partner_id.city', string='City')
    partner_phone = fields.Char(related='partner_id.phone', string='Phone')

    _beat_partner_uniq = models.Constraint('UNIQUE(beat_id, partner_id)', 'A client appears only once per beat.')
