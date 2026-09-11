from odoo import api, fields, models


class FfVisit(models.Model):
    _inherit = 'ff.visit'

    beat_plan_id = fields.Many2one('ff.beat.plan', string='Beat Plan', index=True, ondelete='set null')
    is_planned = fields.Boolean(string='Planned Visit', compute='_compute_is_planned', store=True)

    @api.depends('beat_plan_id.beat_id.line_ids.partner_id', 'partner_id')
    def _compute_is_planned(self):
        for visit in self:
            visit.is_planned = visit.partner_id in visit.beat_plan_id.beat_id.line_ids.partner_id

    @api.model_create_multi
    def create(self, vals_list):
        Plan = self.env['ff.beat.plan'].sudo()
        for vals in vals_list:
            if vals.get('beat_plan_id') or not vals.get('employee_id'):
                continue
            employee = self.env['hr.employee'].sudo().browse(vals['employee_id'])
            check_in = fields.Datetime.to_datetime(vals.get('check_in_at')) or fields.Datetime.now()
            day = employee._ff_to_local(check_in).date()
            plan = Plan.search([('employee_id', '=', employee.id), ('date', '=', day)], limit=1)
            if plan:
                vals['beat_plan_id'] = plan.id
        return super().create(vals_list)
