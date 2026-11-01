from odoo import api, fields, models


class ResPartner(models.Model):
    _inherit = 'res.partner'

    ff_primary_employee_id = fields.Many2one('hr.employee', string='Main Field Employee',
                                             compute='_compute_ff_primary_employee', store=True,
                                             help='First employee assigned to this contact; used to credit '
                                                  'documents created for it.')
    ff_primary_route_id = fields.Many2one('ff.beat', string='Main Route',
                                          compute='_compute_ff_primary_employee', store=True)

    @api.depends('ff_employee_ids', 'ff_beat_line_ids.beat_id')
    def _compute_ff_primary_employee(self):
        for partner in self:
            partner.ff_primary_employee_id = partner.ff_employee_ids[:1].id
            partner.ff_primary_route_id = partner.ff_beat_line_ids.beat_id[:1].id
