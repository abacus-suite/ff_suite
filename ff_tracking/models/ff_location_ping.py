from datetime import timedelta

from odoo import api, fields, models

from odoo.addons.ff_base.tools import get_param, map_link, parse_client_dt

PING_SOURCES = [
    ('background', 'Background'),
    ('foreground', 'Foreground'),
    ('punch', 'Punch'),
    ('visit', 'Visit'),
]


def _num(value, cast=float):
    try:
        return cast(value)
    except (TypeError, ValueError):
        return None


class FfLocationPing(models.Model):
    _name = 'ff.location.ping'
    _description = 'GPS Location Ping'
    _order = 'ts desc, id desc'
    _rec_name = 'ts'

    employee_id = fields.Many2one('hr.employee', required=True, index=True, ondelete='cascade')
    ts = fields.Datetime(string='Time', required=True)
    received_at = fields.Datetime(default=fields.Datetime.now)
    latitude = fields.Float(digits=(10, 7), required=True)
    longitude = fields.Float(digits=(10, 7), required=True)
    accuracy = fields.Float(string='Accuracy (m)')
    speed = fields.Float(string='Speed (m/s)')
    battery = fields.Integer(string='Battery %')
    is_charging = fields.Boolean()
    gps_on = fields.Boolean(string='GPS On', default=True)
    is_mock = fields.Boolean(string='Mock Location')
    source = fields.Selection(PING_SOURCES, default='background', required=True)
    client_uuid = fields.Char(index=True, copy=False)
    map_url = fields.Char(compute='_compute_map_url')

    _client_uuid_uniq = models.Constraint('UNIQUE(client_uuid)', 'This ping was already received.')
    _employee_ts_idx = models.Index('(employee_id, ts)')

    def _compute_map_url(self):
        for ping in self:
            ping.map_url = map_link(ping.env, ping.latitude, ping.longitude)

    @api.model
    def ff_ingest(self, employee, pings):
        """Store a batch of pings sent by the app for ``employee``.

        Pings are idempotent on their client ``uuid`` so the app can safely
        retry offline batches. Returns counts of accepted / duplicate /
        rejected pings.
        """
        Ping = self.sudo()
        now = fields.Datetime.now()
        max_future = now + timedelta(minutes=5)
        uuids = [p.get('uuid') for p in pings if isinstance(p, dict) and p.get('uuid')]
        known = set(Ping.search([('client_uuid', 'in', uuids)]).mapped('client_uuid')) if uuids else set()

        vals_list, seen = [], set()
        duplicates = rejected = 0
        for ping in pings:
            if not isinstance(ping, dict):
                rejected += 1
                continue
            uuid = ping.get('uuid') or False
            if uuid and (uuid in known or uuid in seen):
                duplicates += 1
                continue
            lat, lng = _num(ping.get('lat')), _num(ping.get('lng'))
            try:
                ts = parse_client_dt(ping.get('ts')) or now
            except (TypeError, ValueError):
                ts = None
            if (lat is None or lng is None or ts is None
                    or not (-90 <= lat <= 90 and -180 <= lng <= 180)
                    or (lat == 0 and lng == 0)):
                rejected += 1
                continue
            if uuid:
                seen.add(uuid)
            source = ping.get('source')
            vals_list.append({
                'employee_id': employee.id,
                'ts': min(ts, max_future),
                'latitude': lat,
                'longitude': lng,
                'accuracy': _num(ping.get('accuracy')) or 0.0,
                'speed': _num(ping.get('speed')) or 0.0,
                'battery': _num(ping.get('battery'), int) or 0,
                'is_charging': bool(ping.get('charging')),
                'gps_on': ping.get('gps_on', True) is not False,
                'is_mock': bool(ping.get('mock')),
                'source': source if source in dict(PING_SOURCES) else 'background',
                'client_uuid': uuid,
            })

        records = Ping.create(vals_list) if vals_list else Ping
        if records:
            self.env['ff.employee.status']._ff_apply_pings(employee, records)
        return {'accepted': len(records), 'duplicates': duplicates, 'rejected': rejected}

    @api.model
    def _cron_purge(self):
        days = get_param(self.env, 'ping_retention_days')
        if days <= 0:
            return
        limit = fields.Datetime.now() - timedelta(days=days)
        self.env.cr.execute('DELETE FROM ff_location_ping WHERE ts < %s', [limit])
