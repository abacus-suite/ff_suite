from datetime import timedelta

from odoo import api, fields, models

from odoo.addons.ff_base.tools import get_param, haversine_m

# Movement below this distance is treated as standing still.
MOVE_THRESHOLD_M = 100


class FfEmployeeStatus(models.Model):
    _name = 'ff.employee.status'
    _description = 'Field Employee Live Status'
    _order = 'employee_id'
    _rec_name = 'employee_id'

    employee_id = fields.Many2one('hr.employee', required=True, index=True, ondelete='cascade')
    team_id = fields.Many2one(related='employee_id.ff_team_id', store=True)
    manager_id = fields.Many2one(related='employee_id.parent_id', store=True, string='Manager')

    punched_in = fields.Boolean()
    punched_in_at = fields.Datetime()

    last_ping_at = fields.Datetime(string='Last Ping')
    latitude = fields.Float(digits=(10, 7))
    longitude = fields.Float(digits=(10, 7))
    accuracy = fields.Float(string='Accuracy (m)')
    battery = fields.Integer(string='Battery %')
    is_charging = fields.Boolean()
    gps_on = fields.Boolean(string='GPS On', default=True)
    is_mock = fields.Boolean(string='Mock Location')
    battery_saver = fields.Boolean()
    location_permission = fields.Boolean(default=True)

    anchor_latitude = fields.Float(digits=(10, 7))
    anchor_longitude = fields.Float(digits=(10, 7))
    moved_at = fields.Datetime(string='Last Movement')

    is_inactive = fields.Boolean(string='Inactive', help='Punched in but not moving for longer than the threshold.')
    is_signal_lost = fields.Boolean(string='No Signal', help='Punched in but no ping received recently.')
    is_low_battery = fields.Boolean(compute='_compute_is_low_battery', store=True)
    map_url = fields.Char(compute='_compute_map_url')

    _employee_uniq = models.Constraint('UNIQUE(employee_id)', 'Only one live status per employee.')

    @api.depends('battery', 'last_ping_at')
    def _compute_is_low_battery(self):
        threshold = get_param(self.env, 'low_battery')
        for status in self:
            status.is_low_battery = bool(status.last_ping_at) and status.battery < threshold

    def _compute_map_url(self):
        for status in self:
            status.map_url = status.last_ping_at and 'https://www.google.com/maps?q=%s,%s' % (
                status.latitude, status.longitude) or False

    @api.model
    def _ff_get(self, employee):
        Status = self.sudo()
        status = Status.search([('employee_id', '=', employee.id)], limit=1)
        return status or Status.create({'employee_id': employee.id})

    @api.model
    def _ff_apply_pings(self, employee, pings):
        status = self._ff_get(employee)
        latest = pings.sorted('ts')[-1]
        if status.last_ping_at and latest.ts < status.last_ping_at:
            return status  # late offline batch, live position is already newer
        vals = {
            'last_ping_at': latest.ts,
            'latitude': latest.latitude,
            'longitude': latest.longitude,
            'accuracy': latest.accuracy,
            'battery': latest.battery,
            'is_charging': latest.is_charging,
            'gps_on': latest.gps_on,
            'is_mock': latest.is_mock,
            'is_signal_lost': False,
        }
        no_anchor = not status.anchor_latitude and not status.anchor_longitude
        if no_anchor or haversine_m(status.anchor_latitude, status.anchor_longitude,
                                    latest.latitude, latest.longitude) >= MOVE_THRESHOLD_M:
            vals.update({
                'anchor_latitude': latest.latitude,
                'anchor_longitude': latest.longitude,
                'moved_at': latest.ts,
                'is_inactive': False,
            })
        status.write(vals)
        return status

    @api.model
    def _cron_flag_inactive(self):
        now = fields.Datetime.now()
        idle_limit = now - timedelta(minutes=get_param(self.env, 'idle_threshold'))
        signal_limit = now - timedelta(seconds=max(get_param(self.env, 'ping_interval') * 3, 600))
        Status = self.sudo()
        for status in Status.search([('punched_in', '=', True)]):
            marks = [dt for dt in (status.moved_at, status.punched_in_at) if dt]
            inactive = bool(marks) and max(marks) < idle_limit
            lost = not status.last_ping_at or status.last_ping_at < signal_limit
            if inactive != status.is_inactive or lost != status.is_signal_lost:
                status.write({'is_inactive': inactive, 'is_signal_lost': lost})
        Status.search([
            ('punched_in', '=', False),
            '|', ('is_inactive', '=', True), ('is_signal_lost', '=', True),
        ]).write({'is_inactive': False, 'is_signal_lost': False})
