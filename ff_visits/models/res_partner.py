from odoo import fields, models


class ResPartner(models.Model):
    _inherit = 'res.partner'

    ff_last_visit_at = fields.Datetime(string='Last Field Visit', readonly=True, copy=False)
    ff_last_visit_employee_id = fields.Many2one('hr.employee', string='Last Visited By', readonly=True, copy=False)
    ff_days_since_visit = fields.Integer(string='Days Since Visit', compute='_compute_ff_last_visit_info',
                                         help='-1 = never visited')
    ff_last_visit_label = fields.Char(string='Last Visit', compute='_compute_ff_last_visit_info')
    ff_visit_count = fields.Integer(string='Field Visits', compute='_compute_ff_visit_count')

    def _compute_ff_last_visit_info(self):
        today = fields.Date.context_today(self)
        for partner in self:
            if not partner.ff_last_visit_at:
                partner.ff_days_since_visit = -1
                partner.ff_last_visit_label = self.env._('Never visited')
                continue
            days = (today - fields.Datetime.context_timestamp(partner, partner.ff_last_visit_at).date()).days
            partner.ff_days_since_visit = days
            when = (self.env._('Today') if days <= 0 else self.env._('Yesterday') if days == 1
                    else self.env._('%s days ago', days))
            by = partner.ff_last_visit_employee_id.name
            partner.ff_last_visit_label = '%s · %s' % (when, by) if by else when

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
