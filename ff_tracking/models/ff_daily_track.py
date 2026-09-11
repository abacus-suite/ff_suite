from datetime import timedelta

from odoo import api, fields, models

from odoo.addons.ff_base.tools import get_param, path_distance_km


class FfDailyTrack(models.Model):
    _name = 'ff.daily.track'
    _description = 'Daily Travel Summary'
    _order = 'date desc, employee_id'

    employee_id = fields.Many2one('hr.employee', required=True, index=True, ondelete='cascade')
    team_id = fields.Many2one(related='employee_id.ff_team_id', store=True)
    date = fields.Date(required=True, index=True)
    distance_km = fields.Float(string='Distance (km)', digits=(10, 2))
    ping_count = fields.Integer(string='Pings')
    first_ping_at = fields.Datetime(string='First Ping')
    last_ping_at = fields.Datetime(string='Last Ping')

    _employee_date_uniq = models.Constraint(
        'UNIQUE(employee_id, date)', 'Only one travel summary per employee and day.')

    @api.depends('employee_id', 'date')
    def _compute_display_name(self):
        for track in self:
            track.display_name = '%s - %s' % (track.employee_id.name or '', track.date or '')

    @api.model
    def _ff_compute(self, employee, day):
        """(Re)compute the travelled distance of ``employee`` on local ``day``."""
        start, end = employee._ff_day_bounds(day)
        pings = self.env['ff.location.ping'].sudo().search([
            ('employee_id', '=', employee.id),
            ('ts', '>=', start),
            ('ts', '<', end),
            ('is_mock', '=', False),
        ], order='ts asc')
        Track = self.sudo()
        track = Track.search([('employee_id', '=', employee.id), ('date', '=', day)], limit=1)
        if not pings:
            return track
        vals = {
            'distance_km': path_distance_km(
                [(p.ts, p.latitude, p.longitude, p.accuracy) for p in pings],
                max_accuracy=get_param(self.env, 'max_accuracy'),
            ),
            'ping_count': len(pings),
            'first_ping_at': pings[0].ts,
            'last_ping_at': pings[-1].ts,
        }
        if track:
            track.write(vals)
        else:
            track = Track.create(dict(vals, employee_id=employee.id, date=day))
        return track

    @api.model
    def _cron_compute(self):
        since = fields.Datetime.now() - timedelta(days=2)
        groups = self.env['ff.location.ping'].sudo()._read_group([('ts', '>=', since)], ['employee_id'])
        for (employee,) in groups:
            today = employee._ff_today()
            for day in (today - timedelta(days=1), today):
                self._ff_compute(employee, day)
