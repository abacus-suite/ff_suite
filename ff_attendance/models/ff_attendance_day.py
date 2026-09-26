"""One row per person per day, with the punches of that day behind it.

Somebody who punches in and out several times leaves several attendance
records, which makes the list hard to read. This gathers them into the day
they belong to: the day is what a manager looks at, and the punches are there
when they open it.
"""
from odoo import api, fields, models

DAY_STATUSES = [
    ('present', 'Present'),
    ('late', 'Late'),
    ('half_day', 'Half Day'),
    ('absent', 'Absent'),
]


class FfAttendanceDay(models.Model):
    _name = 'ff.attendance.day'
    _description = 'Attendance by Day'
    _auto = False
    _order = 'date desc, employee_id'
    _rec_name = 'employee_id'

    employee_id = fields.Many2one('hr.employee', string='Employee', readonly=True)
    team_id = fields.Many2one('ff.team', string='Team', readonly=True)
    company_id = fields.Many2one('res.company', string='Company', readonly=True)
    date = fields.Date(string='Day', readonly=True)
    first_check_in = fields.Datetime(string='First Check In', readonly=True)
    last_check_out = fields.Datetime(string='Last Check Out', readonly=True)
    punch_count = fields.Integer(string='Punches', readonly=True)
    worked_hours = fields.Float(string='Worked Hours', readonly=True)
    late_minutes = fields.Integer(string='Late (min)', readonly=True)
    day_status = fields.Selection(DAY_STATUSES, string='Day Status', readonly=True)
    in_address = fields.Char(string='First Punch-in Address', readonly=True)
    out_address = fields.Char(string='Last Punch-out Address', readonly=True)
    vehicle_type = fields.Char(string='Vehicle', readonly=True)
    odometer_km = fields.Float(string='Odometer km', readonly=True)
    still_in = fields.Boolean(string='Still Checked In', readonly=True)

    attendance_ids = fields.One2many('hr.attendance', string='Punches', compute='_compute_attendance_ids')
    distance_km = fields.Float(string='Travelled (km)', compute='_compute_distance_km')

    def _compute_attendance_ids(self):
        """The punches of that person on that day, earliest first."""
        Attendance = self.env['hr.attendance']
        for row in self:
            start, end = row.employee_id._ff_day_bounds(row.date) if row.employee_id and row.date else (False, False)
            row.attendance_ids = Attendance.search([
                ('employee_id', '=', row.employee_id.id),
                ('check_in', '>=', start), ('check_in', '<', end),
            ], order='check_in') if start else Attendance.browse()

    def _compute_distance_km(self):
        Track = self.env['ff.daily.track'] if 'ff.daily.track' in self.env else None
        for row in self:
            track = Track.search([('employee_id', '=', row.employee_id.id), ('date', '=', row.date)], limit=1) \
                if Track else False
            row.distance_km = track.distance_km if track else 0.0

    @api.depends('employee_id', 'date')
    def _compute_display_name(self):
        for row in self:
            row.display_name = '%s - %s' % (row.employee_id.name or '', row.date or '')

    def action_open_punches(self):
        """The punches of this day, as ordinary attendance records."""
        self.ensure_one()
        return {
            'type': 'ir.actions.act_window',
            'name': self.display_name,
            'res_model': 'hr.attendance',
            'view_mode': 'list,form',
            'domain': [('id', 'in', self.attendance_ids.ids)],
        }

    @property
    def _table_query(self):
        return """
            SELECT MIN(a.id) AS id,
                   a.employee_id AS employee_id,
                   MIN(e.ff_team_id) AS team_id,
                   MIN(e.company_id) AS company_id,
                   ((a.check_in AT TIME ZONE 'UTC') AT TIME ZONE COALESCE(rr.tz, 'UTC'))::date AS date,
                   MIN(a.check_in) AS first_check_in,
                   MAX(a.check_out) AS last_check_out,
                   COUNT(*) AS punch_count,
                   COALESCE(SUM(a.worked_hours), 0) AS worked_hours,
                   COALESCE(MAX(a.ff_late_minutes), 0) AS late_minutes,
                   CASE WHEN BOOL_OR(a.ff_day_status = 'half_day') THEN 'half_day'
                        WHEN BOOL_OR(a.ff_day_status = 'late') THEN 'late'
                        ELSE 'present' END AS day_status,
                   (ARRAY_REMOVE(ARRAY_AGG(a.ff_in_address ORDER BY a.check_in), NULL))[1] AS in_address,
                   (ARRAY_REMOVE(ARRAY_AGG(a.ff_out_address ORDER BY a.check_in DESC), NULL))[1] AS out_address,
                   (ARRAY_REMOVE(ARRAY_AGG(a.ff_vehicle_type ORDER BY a.check_in), NULL))[1] AS vehicle_type,
                   COALESCE(SUM(a.ff_odometer_km), 0) AS odometer_km,
                   BOOL_OR(a.check_out IS NULL) AS still_in
              FROM hr_attendance a
              JOIN hr_employee e ON e.id = a.employee_id
         LEFT JOIN resource_resource rr ON rr.id = e.resource_id
             WHERE a.check_in IS NOT NULL
          GROUP BY a.employee_id, 5, rr.tz
        """
