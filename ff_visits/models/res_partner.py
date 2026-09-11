from odoo import fields, models


class ResPartner(models.Model):
    _inherit = 'res.partner'

    ff_last_visit_at = fields.Datetime(string='Last Field Visit', readonly=True, copy=False)
    ff_visit_count = fields.Integer(string='Field Visits', compute='_compute_ff_visit_count')

    def _compute_ff_visit_count(self):
        counts = dict(self.env['ff.visit'].sudo()._read_group(
            [('partner_id', 'in', self.ids)], ['partner_id'], ['__count']))
        for partner in self:
            partner.ff_visit_count = counts.get(partner, 0)

    def action_ff_view_visits(self):
        self.ensure_one()
        return {
            'type': 'ir.actions.act_window',
            'name': self.env._('Field Visits'),
            'res_model': 'ff.visit',
            'view_mode': 'list,form',
            'domain': [('partner_id', '=', self.id)],
        }
