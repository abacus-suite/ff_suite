from odoo import fields, models

from .ff_route_plan import week_of_month

WEEKDAYS = [
    ('0', 'Monday'), ('1', 'Tuesday'), ('2', 'Wednesday'), ('3', 'Thursday'),
    ('4', 'Friday'), ('5', 'Saturday'), ('6', 'Sunday'),
]
WEEKS = [
    ('all', 'Every week'), ('1', '1st week'), ('2', '2nd week'),
    ('3', '3rd week'), ('4', '4th week'), ('5', '5th week'),
]


class FfRoutePlanTemplate(models.Model):
    """Reusable weekly pattern, e.g. Mon: Route A, Tue: Route B (optionally per week of the month)."""
    _name = 'ff.route.plan.template'
    _description = 'Route Plan Template'
    _order = 'name'

    name = fields.Char(required=True)
    employee_id = fields.Many2one('hr.employee', string='Suggested Employee',
                                  help='Optional: pre-selected when applying. The template can be used for anyone.')
    line_ids = fields.One2many('ff.route.plan.template.line', 'template_id', string='Routes', copy=True)
    note = fields.Text()
    company_id = fields.Many2one('res.company', required=True, default=lambda self: self.env.company)
    active = fields.Boolean(default=True)


class FfRoutePlanTemplateLine(models.Model):
    _name = 'ff.route.plan.template.line'
    _description = 'Route Plan Template Line'
    _order = 'week, weekday, sequence, id'

    template_id = fields.Many2one('ff.route.plan.template', required=True, index=True, ondelete='cascade')
    sequence = fields.Integer(default=10)
    week = fields.Selection(WEEKS, required=True, default='all')
    weekday = fields.Selection(WEEKDAYS, required=True, default='0')
    beat_id = fields.Many2one('ff.beat', string='Route', required=True)

    def _ff_matches(self, day):
        self.ensure_one()
        return self.weekday == str(day.weekday()) and (self.week == 'all' or int(self.week) == week_of_month(day))
