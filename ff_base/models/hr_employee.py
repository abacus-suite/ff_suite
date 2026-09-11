from datetime import datetime, time, timedelta

import pytz

from odoo import fields, models


class HrEmployee(models.Model):
    _inherit = 'hr.employee'

    ff_employee_code = fields.Char(string='Field Employee Code', copy=False, tracking=True)
    ff_team_id = fields.Many2one('ff.team', string='Field Team', index=True, tracking=True)
    ff_designation_id = fields.Many2one('ff.designation', string='Field Designation', tracking=True)
    ff_tracking_enabled = fields.Boolean(
        string='Location Tracking', default=True,
        help='Track GPS location from the mobile app while the employee is punched in.',
    )
    ff_device_ids = fields.One2many('ff.device', 'employee_id', string='Devices')

    _ff_employee_code_uniq = models.Constraint(
        'UNIQUE(ff_employee_code, company_id)',
        'The field employee code must be unique per company.',
    )

    def _ff_subordinates(self):
        """All employees below ``self`` in the reporting hierarchy."""
        if not self:
            return self
        return self.env['hr.employee'].sudo().search([('id', 'child_of', self.ids)]) - self

    def _ff_is_manager_of(self, employee):
        self.ensure_one()
        return employee in self._ff_subordinates()

    # Timezone helpers: Odoo stores naive UTC, the field day is local.
    def _ff_tz(self):
        self.ensure_one()
        return pytz.timezone(self.tz or 'UTC')

    def _ff_today(self):
        return datetime.now(pytz.utc).astimezone(self._ff_tz()).date()

    def _ff_to_local(self, dt):
        return pytz.utc.localize(dt).astimezone(self._ff_tz()).replace(tzinfo=None)

    def _ff_day_bounds(self, day):
        """Naive-UTC [start, end) of the local calendar ``day``."""
        tz = self._ff_tz()
        start = tz.localize(datetime.combine(day, time.min)).astimezone(pytz.utc)
        end = tz.localize(datetime.combine(day + timedelta(days=1), time.min)).astimezone(pytz.utc)
        return start.replace(tzinfo=None), end.replace(tzinfo=None)
