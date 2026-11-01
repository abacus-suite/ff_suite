"""Holidays that differ by region.

Kerala and Tamil Nadu do not share a calendar: Onam is a holiday in Kochi and
not in Chennai, Pongal the other way round. A single company-wide list would
mark somebody absent on a day their own region had off, or excuse them on a day
it did not, so a holiday names the teams it applies to and applies to nobody
else. Teams are the regions here, and a holiday set on a team covers its sub
teams, so "South India" can be given once and not eleven times.
"""
from odoo import api, fields, models


class FfHoliday(models.Model):
    _name = 'ff.holiday'
    _description = 'Regional Holiday'
    _order = 'date, name'

    name = fields.Char(required=True, translate=True)
    date = fields.Date(required=True, index=True)
    team_ids = fields.Many2many(
        'ff.team', 'ff_holiday_team_rel', 'holiday_id', 'team_id', string='Regions',
        help='The teams this holiday applies to, and their sub teams. Leave empty for everybody.')
    company_id = fields.Many2one('res.company', required=True, default=lambda self: self.env.company)
    active = fields.Boolean(default=True)

    @api.depends('name', 'date')
    def _compute_display_name(self):
        for holiday in self:
            holiday.display_name = '%s (%s)' % (holiday.name, holiday.date or '')

    @api.model
    def _ff_for(self, employee, day):
        """The holiday that falls on ``day`` for this employee, if any."""
        holidays = self.sudo().search([
            ('date', '=', day), ('company_id', 'in', (False, employee.company_id.id)),
        ])
        if not holidays:
            return self.browse()
        # A team, and every team above it: a holiday given to the parent covers the child.
        team = employee.sudo().ff_team_id
        chain = self.env['ff.team']
        while team and team not in chain:
            chain |= team
            team = team.parent_id
        return holidays.filtered(lambda h: not h.team_ids or (h.team_ids & chain))[:1]
