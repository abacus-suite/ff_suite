from odoo import api, fields, models


class FfVisit(models.Model):
    _inherit = 'ff.visit'

    beat_plan_id = fields.Many2one('ff.beat.plan', string='Route Plan', index=True, ondelete='set null')
    is_planned = fields.Boolean(string='Planned Visit', compute='_compute_is_planned', store=True)

    @api.depends('beat_plan_id.customer_line_ids.partner_id', 'beat_plan_id.customer_line_ids.selected', 'partner_id')
    def _compute_is_planned(self):
        for visit in self:
            visit.is_planned = visit.partner_id in visit.beat_plan_id.customer_line_ids.filtered('selected').partner_id

    @api.model_create_multi
    def create(self, vals_list):
        Day = self.env['ff.beat.plan'].sudo()
        for vals in vals_list:
            if vals.get('beat_plan_id') or not vals.get('employee_id'):
                continue
            employee = self.env['hr.employee'].sudo().browse(vals['employee_id'])
            check_in = fields.Datetime.to_datetime(vals.get('check_in_at')) or fields.Datetime.now()
            days = Day.search([('employee_id', '=', employee.id), ('date', '=', employee._ff_to_local(check_in).date())])
            if days:
                partner_id = vals.get('partner_id')
                match = days.filtered(lambda d: partner_id in d.customer_line_ids.filtered('selected').partner_id.ids)
                vals['beat_plan_id'] = (match or days)[:1].id
        visits = super().create(vals_list)
        Line = self.env['ff.route.plan.customer'].sudo()
        for visit in visits.sudo().filtered('beat_plan_id'):
            line = Line.search([
                ('employee_id', '=', visit.employee_id.id), ('date', '=', visit.beat_plan_id.date),
                ('partner_id', '=', visit.partner_id.id), ('visit_id', '=', False),
            ], limit=1)
            if line:
                line.visit_id = visit
        return visits
