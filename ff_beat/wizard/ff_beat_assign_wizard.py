from datetime import timedelta

from odoo import api, fields, models
from odoo.exceptions import ValidationError


class FfBeatAssignWizard(models.TransientModel):
    _name = 'ff.beat.assign.wizard'
    _description = 'Plan Route for Employees'

    beat_id = fields.Many2one('ff.beat', string='Route', required=True)
    employee_ids = fields.Many2many('hr.employee', string='Employees', required=True,
                                    compute='_compute_employee_ids', store=True, readonly=False)
    date_from = fields.Date(required=True, default=fields.Date.context_today)
    date_to = fields.Date(required=True, default=lambda self: fields.Date.context_today(self) + timedelta(days=6))
    skip_week_off = fields.Boolean(string='Skip Week Offs', default=True,
                                   help="Uses each employee's shift week offs (Sunday when no shift).")
    overwrite = fields.Boolean(string='Replace Existing Plans',
                               help='Replace plans on those days that have no visits yet.')
    assign_route = fields.Boolean(string='Add Route to Employees', default=True,
                                  help="Also add this route to the employees' Assigned Routes.")

    @api.depends('beat_id')
    def _compute_employee_ids(self):
        for wizard in self:
            if wizard.beat_id and not wizard.employee_ids:
                wizard.employee_ids = wizard.beat_id.employee_ids

    @api.constrains('date_from', 'date_to')
    def _check_dates(self):
        for wizard in self:
            if wizard.date_to < wizard.date_from:
                raise ValidationError(self.env._('The end date must be after the start date.'))
            if (wizard.date_to - wizard.date_from).days > 92:
                raise ValidationError(self.env._('Plan at most 3 months at a time.'))

    def _is_off(self, employee, day):
        shift = employee.ff_shift_id
        return shift._ff_is_week_off(day) if shift else day.weekday() == 6

    def action_assign(self):
        self.ensure_one()
        if self.assign_route:
            self.employee_ids.sudo().write({'ff_route_ids': [(4, self.beat_id.id)]})
        Plan = self.env['ff.beat.plan']
        for employee in self.employee_ids:
            day = self.date_from
            while day <= self.date_to:
                if not (self.skip_week_off and self._is_off(employee, day)):
                    existing = Plan.search([('employee_id', '=', employee.id), ('date', '=', day)], limit=1)
                    if not existing:
                        Plan.create({'employee_id': employee.id, 'beat_id': self.beat_id.id, 'date': day})
                    elif self.overwrite and not existing.visit_ids:
                        existing.beat_id = self.beat_id
                day += timedelta(days=1)
        return {
            'type': 'ir.actions.act_window',
            'name': self.env._('Route Plans'),
            'res_model': 'ff.beat.plan',
            'view_mode': 'list,calendar,form',
            'domain': [('beat_id', '=', self.beat_id.id),
                       ('date', '>=', self.date_from), ('date', '<=', self.date_to)],
        }
