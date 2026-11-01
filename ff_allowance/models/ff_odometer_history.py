from dateutil.relativedelta import relativedelta

from odoo import api, fields, models


class FfOdometerHistory(models.Model):
    """One employee's meter for one day: what they entered, and the distance the phone tracked."""
    _name = 'ff.odometer.history'
    _description = 'Odometer History'
    _order = 'date desc, employee_id'

    employee_id = fields.Many2one('hr.employee', required=True, index=True, ondelete='cascade')
    date = fields.Date(required=True, index=True)
    opening = fields.Float(string='Opening Reading', digits=(12, 1))
    closing = fields.Float(string='Closing Reading', digits=(12, 1))
    odometer_km = fields.Float(string='Odometer km', digits=(12, 1), compute='_compute_odometer_km', store=True,
                               help='Closing less opening. Empty when the day was closed by the app (no reading).')
    geo_km = fields.Float(string='Tracked km (GPS)', digits=(12, 1))
    auto_closed = fields.Boolean(string='Closed by the app',
                                 help='The day was closed automatically, so there is no closing reading.')
    na = fields.Boolean(string='Odometer not available', compute='_compute_odometer_km', store=True)

    _day_uniq = models.Constraint('UNIQUE(employee_id, date)', 'One odometer record per employee and day.')

    @api.depends('opening', 'closing', 'auto_closed')
    def _compute_odometer_km(self):
        for rec in self:
            usable = bool(rec.opening and rec.closing and not rec.auto_closed and rec.closing >= rec.opening)
            rec.na = not usable
            rec.odometer_km = round(rec.closing - rec.opening, 1) if usable else 0.0

    @api.model
    def _ff_refresh(self, employee, day):
        """Read the day's punches and keep this employee's record for the day up to date."""
        employee = employee.sudo()
        start, end = employee._ff_day_bounds(day)
        attendances = self.env['hr.attendance'].sudo().search([
            ('employee_id', '=', employee.id), ('check_in', '>=', start), ('check_in', '<', end)], order='check_in')
        opening = next((a.ff_in_odometer for a in attendances if a.ff_in_odometer), 0.0)
        closed = attendances.filtered('check_out')
        closing = next((a.ff_out_odometer for a in reversed(list(closed)) if a.ff_out_odometer), 0.0)
        auto = bool(closed[-1:].ff_auto_closed) if closed else False
        geo = 0.0
        if 'ff.daily.track' in self.env:
            track = self.env['ff.daily.track'].sudo()._ff_compute(employee, day)
            geo = round(track.distance_km, 1) if track else 0.0
        values = {'opening': opening, 'closing': closing, 'geo_km': geo, 'auto_closed': auto}
        rec = self.sudo().search([('employee_id', '=', employee.id), ('date', '=', day)], limit=1)
        if rec:
            rec.write(values)
        else:
            rec = self.sudo().create(dict(values, employee_id=employee.id, date=day))
        return rec

    @api.model
    def _cron_refresh(self):
        since = fields.Datetime.now() - relativedelta(days=2)
        for employee in self.env['hr.attendance'].sudo().search([('check_in', '>=', since)]).employee_id:
            today = employee._ff_today()
            for day in (today, today - relativedelta(days=1)):
                self._ff_refresh(employee, day)
