from datetime import timedelta

from odoo import api, fields, models
from odoo.exceptions import UserError, ValidationError

from ..models.ff_route_plan import month_start


class FfRoutePlanApplyWizard(models.TransientModel):
    _name = 'ff.route.plan.apply.wizard'
    _description = 'Apply Route Plan Template'

    template_id = fields.Many2one('ff.route.plan.template', string='Template', required=True)
    employee_ids = fields.Many2many('hr.employee', string='Employees', required=True)
    date_from = fields.Date(required=True, default=fields.Date.context_today)
    date_to = fields.Date(required=True, default=lambda self: fields.Date.context_today(self) + timedelta(days=6))
    skip_week_off = fields.Boolean(string='Skip Week Offs', default=True)
    overwrite = fields.Boolean(string='Replace Existing Days',
                               help='Replace already planned days that have no visits yet.')

    @api.onchange('template_id')
    def _onchange_template_id(self):
        if self.template_id.employee_id and not self.employee_ids:
            self.employee_ids = self.template_id.employee_id

    @api.constrains('date_from', 'date_to')
    def _check_dates(self):
        for wizard in self:
            if wizard.date_to < wizard.date_from:
                raise ValidationError(self.env._('The end date must be after the start date.'))
            if (wizard.date_to - wizard.date_from).days > 92:
                raise ValidationError(self.env._('Apply at most 3 months at a time.'))

    def action_apply(self):
        self.ensure_one()
        lines = self.template_id.line_ids.sorted('sequence')
        if not lines:
            raise UserError(self.env._('The template has no routes.'))
        problems = []
        for employee in self.employee_ids:
            allowed = employee.ff_route_ids
            missing = (lines.beat_id - allowed) if allowed else self.env['ff.beat']
            if missing:
                problems.append('%s: %s' % (employee.name, ', '.join(missing.mapped('display_name'))))
        if problems:
            raise UserError(self.env._('These template routes are not assigned to the employees:\n%s', '\n'.join(problems)))

        Plan = self.env['ff.route.plan']
        for employee in self.employee_ids:
            Plan._ff_get(employee, self.date_from)._ff_fill(
                lambda day: [(line.beat_id, None) for line in lines if line._ff_matches(day)],
                self.date_from, self.date_to, overwrite=self.overwrite, skip_week_off=self.skip_week_off)
        plans = Plan.search([
            ('employee_id', 'in', self.employee_ids.ids),
            ('month', '>=', month_start(self.date_from)), ('month', '<=', month_start(self.date_to)),
        ])
        return {
            'type': 'ir.actions.act_window',
            'name': self.env._('Route Plans'),
            'res_model': 'ff.route.plan',
            'view_mode': 'list,form',
            'domain': [('id', 'in', plans.ids)],
        }
