from odoo import api, fields, models

from odoo.addons.ff_base.tools import parse_client_dt

COMPLIANCE_EVENTS = [
    ('gps_off', 'GPS turned off'),
    ('gps_on', 'GPS turned on'),
    ('battery_saver_on', 'Battery saver on'),
    ('battery_saver_off', 'Battery saver off'),
    ('permission_revoked', 'Location permission revoked'),
    ('permission_granted', 'Location permission granted'),
    ('mock_location', 'Mock location detected'),
    ('time_tampered', 'Device time changed'),
    ('app_killed', 'App stopped by system'),
    ('low_battery', 'Low battery'),
]

# How each event changes the employee live status.
STATUS_EFFECTS = {
    'gps_off': {'gps_on': False},
    'gps_on': {'gps_on': True},
    'battery_saver_on': {'battery_saver': True},
    'battery_saver_off': {'battery_saver': False},
    'permission_revoked': {'location_permission': False},
    'permission_granted': {'location_permission': True},
    'mock_location': {'is_mock': True},
}


class FfComplianceLog(models.Model):
    _name = 'ff.compliance.log'
    _description = 'Field App Compliance Event'
    _order = 'ts desc, id desc'
    _rec_name = 'event'

    employee_id = fields.Many2one('hr.employee', required=True, index=True, ondelete='cascade')
    team_id = fields.Many2one(related='employee_id.ff_team_id', store=True)
    ts = fields.Datetime(string='Time', required=True, default=fields.Datetime.now)
    event = fields.Selection(COMPLIANCE_EVENTS, required=True)
    detail = fields.Char()
    client_uuid = fields.Char(index=True, copy=False)

    _client_uuid_uniq = models.Constraint('UNIQUE(client_uuid)', 'This event was already received.')

    @api.model
    def ff_log(self, employee, events):
        Log = self.sudo()
        valid = dict(COMPLIANCE_EVENTS)
        uuids = [e.get('uuid') for e in events if isinstance(e, dict) and e.get('uuid')]
        known = set(Log.search([('client_uuid', 'in', uuids)]).mapped('client_uuid')) if uuids else set()
        vals_list, seen = [], set()
        duplicates = rejected = 0
        for event in events:
            if not isinstance(event, dict) or event.get('type') not in valid:
                rejected += 1
                continue
            uuid = event.get('uuid') or False
            if uuid and (uuid in known or uuid in seen):
                duplicates += 1
                continue
            try:
                ts = parse_client_dt(event.get('ts')) or fields.Datetime.now()
            except (TypeError, ValueError):
                rejected += 1
                continue
            if uuid:
                seen.add(uuid)
            vals_list.append({
                'employee_id': employee.id,
                'ts': ts,
                'event': event['type'],
                'detail': (event.get('detail') or '')[:250] or False,
                'client_uuid': uuid,
            })
        logs = Log.create(vals_list) if vals_list else Log
        status_vals = {}
        for log in logs.sorted('ts'):
            status_vals.update(STATUS_EFFECTS.get(log.event, {}))
        if status_vals:
            self.env['ff.employee.status']._ff_get(employee).write(status_vals)
        return {'accepted': len(logs), 'duplicates': duplicates, 'rejected': rejected}
