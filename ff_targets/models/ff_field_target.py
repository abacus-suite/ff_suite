"""Bottles and outlets a manager gives to people under them, for a month or one week of it."""
import calendar

from odoo import api, fields, models
from odoo.exceptions import ValidationError

PERIODS = [('month', 'Monthly'), ('week', 'Weekly')]


def week_bounds(first_of_month, week):
    """The dates of week 1 to 4 of a month: 1-7, 8-14, 15-21 and 22 to the end."""
    last = calendar.monthrange(first_of_month.year, first_of_month.month)[1]
    start_day = 1 + 7 * (week - 1)
    end_day = last if week >= 4 else start_day + 6
    return first_of_month.replace(day=start_day), first_of_month.replace(day=end_day)


class FfFieldTarget(models.Model):
    _name = 'ff.field.target'
    _description = 'Bottles and Outlets Target'
    _order = 'month desc, employee_id, week'

    employee_id = fields.Many2one('hr.employee', required=True, index=True, ondelete='cascade')
    period = fields.Selection(PERIODS, required=True, default='month')
    month = fields.Date(required=True, index=True, help='Any day of the month; saved as its first day.')
    week = fields.Integer(help='1 to 4 for a weekly target; 0 for the whole month.')
    bottle_target = fields.Integer(string='No. of Bottles')
    outlet_target = fields.Integer(string='No. of Outlets Onboarded')
    assigned_by_id = fields.Many2one('hr.employee', string='Assigned By', readonly=True)
    company_id = fields.Many2one(related='employee_id.company_id', store=True)

    @api.model_create_multi
    def create(self, vals_list):
        for vals in vals_list:
            if vals.get('month'):
                vals['month'] = fields.Date.to_date(vals['month']).replace(day=1)
            if vals.get('period') == 'month':
                vals['week'] = 0
        return super().create(vals_list)

    @api.constrains('week', 'period')
    def _check_week(self):
        for target in self:
            if target.period == 'week' and target.week not in (1, 2, 3, 4):
                raise ValidationError(self.env._('A weekly target needs a week from 1 to 4.'))

    def ff_window(self):
        self.ensure_one()
        if self.period == 'week' and self.week:
            return week_bounds(self.month, self.week)
        last = calendar.monthrange(self.month.year, self.month.month)[1]
        return self.month, self.month.replace(day=last)

    @api.model
    def ff_actual(self, employee, start, end):
        """Bottles in the POs sent to distributors and outlets onboarded, between two local dates."""
        env = self.env
        low = employee._ff_day_bounds(start)[0]
        high = employee._ff_day_bounds(end)[1]
        bottles = 0.0
        if 'ff.demand.line' in env:
            lines = env['ff.demand.line'].sudo().search([
                ('employee_id', '=', employee.id), ('date', '>=', low), ('date', '<', high),
                ('state', '!=', 'cancelled')])
            bottles = sum(l.quantity for l in lines if not getattr(l, 'is_foc', False))
        outlets = 0
        Partner = env['res.partner'].sudo().with_context(active_test=False)
        if 'ff_onboarded_date' in Partner._fields:
            outlets = Partner.search_count([
                ('ff_created_by_employee_id', '=', employee.id),
                ('ff_onboarded_date', '>=', start), ('ff_onboarded_date', '<=', end)])
        return {'bottles': int(round(bottles)), 'outlets': outlets}
