from odoo import api, fields, models
from odoo.exceptions import ValidationError

WEEKDAY_FIELDS = ['off_mon', 'off_tue', 'off_wed', 'off_thu', 'off_fri', 'off_sat', 'off_sun']


class FfShift(models.Model):
    _name = 'ff.shift'
    _description = 'Field Shift'
    _order = 'start_time, name'

    name = fields.Char(required=True)
    start_time = fields.Float(string='Start', required=True, default=9.0)
    end_time = fields.Float(string='End', required=True, default=18.0)
    grace_minutes = fields.Integer(string='Grace (min)', default=10,
                                   help='Punching in later than start + grace is marked Late.')
    half_day_hours = fields.Float(string='Half Day Below (h)', default=4.0,
                                  help='Days with fewer worked hours are marked Half Day.')
    off_mon = fields.Boolean(string='Mon')
    off_tue = fields.Boolean(string='Tue')
    off_wed = fields.Boolean(string='Wed')
    off_thu = fields.Boolean(string='Thu')
    off_fri = fields.Boolean(string='Fri')
    off_sat = fields.Boolean(string='Sat')
    off_sun = fields.Boolean(string='Sun', default=True)
    company_id = fields.Many2one('res.company', required=True, default=lambda self: self.env.company)
    active = fields.Boolean(default=True)

    @api.constrains('start_time', 'end_time')
    def _check_times(self):
        for shift in self:
            if not (0 <= shift.start_time < 24 and 0 <= shift.end_time <= 24):
                raise ValidationError(self.env._('Shift times must be between 00:00 and 24:00.'))

    def _ff_is_week_off(self, day):
        self.ensure_one()
        return bool(self[WEEKDAY_FIELDS[day.weekday()]])

    def _ff_start_minutes(self):
        self.ensure_one()
        return min(int(round(self.start_time * 60)), 24 * 60 - 1)
