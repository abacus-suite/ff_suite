from datetime import date, timedelta
from odoo import api, fields, models, _
from odoo.exceptions import UserError


class WeeklyChillerReportWizard(models.TransientModel):
    _name = 'weekly.chiller.report.wizard'
    _description = 'Weekly Chiller Update Report Wizard'

    date_from = fields.Date(
        string='Date From',
        required=True,
        default=lambda self: fields.Date.today() - timedelta(days=7),
    )
    date_to = fields.Date(
        string='Date To',
        required=True,
        default=fields.Date.today,
    )
    team_ids = fields.Many2many(
        'ff.team',
        'weekly_chiller_report_wizard_team_rel',
        'wizard_id',
        'team_id',
        string='Teams',
        help='Optional: Filter visits by field teams. Leave empty for all teams.',
    )
    employee_ids = fields.Many2many(
        'hr.employee',
        'weekly_chiller_report_wizard_employee_rel',
        'wizard_id',
        'employee_id',
        string='Employees',
        help='Optional: Select one or multiple employees. Leave empty to include all employees in the selected team/company.',
    )

    @api.onchange('team_ids')
    def _onchange_team_ids(self):
        """Update domain for employee_ids based on selected teams."""
        if self.team_ids:
            # Clear selected employees that do not belong to the selected teams
            if self.employee_ids:
                valid_employees = self.employee_ids.filtered(lambda e: e.ff_team_id in self.team_ids)
                self.employee_ids = valid_employees
            return {'domain': {'employee_ids': [('ff_team_id', 'in', self.team_ids.ids)]}}
        return {'domain': {'employee_ids': []}}

    def action_print_pdf(self):
        """Generate and print the Weekly Chiller Update PDF report."""
        self.ensure_one()
        if self.date_from and self.date_to and self.date_from > self.date_to:
            raise UserError(_("Date From cannot be later than Date To."))

        data = {
            'form': {
                'id': self.id,
                'date_from': self.date_from,
                'date_to': self.date_to,
                'team_ids': self.team_ids.ids,
                'employee_ids': self.employee_ids.ids,
            }
        }
        return self.env.ref('l4e_weekly_chiller_report.action_report_weekly_chiller').report_action(self, data=data)
