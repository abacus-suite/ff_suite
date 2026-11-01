"""Alerts to managers, raised from what the field data already records."""
from datetime import timedelta

from odoo import api, fields, models

KINDS = [
    ('inactive', 'Not moving'),
    ('no_signal', 'No signal'),
    ('gps_off', 'GPS turned off'),
    ('permission_revoked', 'Location permission removed'),
    ('mock_location', 'Fake GPS'),
    ('time_tampered', 'Phone clock changed'),
    ('app_killed', 'App stopped'),
    ('offsite_visit', 'Offsite visit'),
]
# Compliance events that are worth a manager's attention while someone is on duty.
EVENT_KINDS = {'gps_off', 'permission_revoked', 'mock_location', 'time_tampered', 'app_killed'}


def _param(env, key, default):
    raw = env['ir.config_parameter'].sudo().get_param('ff_alerts.%s' % key)
    if raw in (None, False, ''):
        return default
    if isinstance(default, bool):
        return raw not in ('False', '0', 'false')
    try:
        return int(raw)
    except (TypeError, ValueError):
        return default


class FfAlert(models.Model):
    _name = 'ff.alert'
    _description = 'Field Staff Alert'
    _order = 'create_date desc, id desc'
    _rec_name = 'message'

    employee_id = fields.Many2one('hr.employee', required=True, index=True, ondelete='cascade')
    team_id = fields.Many2one(related='employee_id.ff_team_id', store=True)
    manager_id = fields.Many2one('hr.employee', string='Told', index=True, ondelete='set null')
    kind = fields.Selection(KINDS, required=True, index=True)
    message = fields.Char(required=True)
    res_model = fields.Char()
    res_id = fields.Integer()
    seen = fields.Boolean(index=True)

    def action_mark_seen(self):
        self.write({'seen': True})

    def action_open_record(self):
        self.ensure_one()
        if not self.res_model or not self.res_id:
            return False
        return {'type': 'ir.actions.act_window', 'res_model': self.res_model, 'res_id': self.res_id,
                'view_mode': 'form', 'target': 'current'}

    # ------------------------------------------------------------------
    @api.model
    def ff_raise(self, employee, kind, message, record=None):
        """Tell the employee's manager - once per kind within the repeat window."""
        if not _param(self.env, 'enabled', True) or not _param(self.env, 'kind_%s' % kind, True):
            return self.browse()
        employee = employee.sudo()
        repeat = _param(self.env, 'repeat_minutes', 60)
        recent = self.sudo().search_count([
            ('employee_id', '=', employee.id), ('kind', '=', kind),
            ('create_date', '>=', fields.Datetime.now() - timedelta(minutes=repeat))])
        if recent and kind != 'offsite_visit':
            return self.browse()
        manager = employee.parent_id
        alert = self.sudo().create({
            'employee_id': employee.id,
            'manager_id': manager.id or False,
            'kind': kind,
            'message': message,
            'res_model': record._name if record else False,
            'res_id': record.id if record else False,
        })
        if manager and 'ff.notification' in self.env:
            self.env['ff.notification'].sudo().ff_push(
                dict(KINDS)[kind], message, kind='info', employee=manager, record=record)
        return alert

    @api.model
    def _cron_check_staff(self):
        """Who, on duty, has stopped moving or gone silent since the last run."""
        Status = self.env['ff.employee.status'].sudo()
        for status in Status.search([('punched_in', '=', True)]):
            employee = status.employee_id
            if status.is_inactive:
                since = status.moved_at or status.punched_in_at
                minutes = int((fields.Datetime.now() - since).total_seconds() // 60) if since else 0
                self.ff_raise(employee, 'inactive', '%s has not moved for %d minutes.' % (employee.name, minutes))
            if status.is_signal_lost:
                self.ff_raise(employee, 'no_signal', '%s has sent no location since %s.' % (
                    employee.name, employee._ff_to_local(status.last_ping_at).strftime('%H:%M')
                    if status.last_ping_at else 'punching in'))
            if status.gps_on is False:
                self.ff_raise(employee, 'gps_off', '%s has GPS switched off.' % employee.name)
            if status.location_permission is False:
                self.ff_raise(employee, 'permission_revoked', '%s removed location permission for the app.' % employee.name)

    @api.autovacuum
    def _gc_alerts(self):
        self.sudo().search([('create_date', '<', fields.Datetime.now() - timedelta(days=90))]).unlink()


class FfComplianceLog(models.Model):
    _inherit = 'ff.compliance.log'

    @api.model_create_multi
    def create(self, vals_list):
        logs = super().create(vals_list)
        Alert = self.env['ff.alert']
        for log in logs.filtered(lambda row: row.event in EVENT_KINDS):
            status = self.env['ff.employee.status'].sudo().search([('employee_id', '=', log.employee_id.id)], limit=1)
            if log.event in ('mock_location', 'time_tampered') or (status and status.punched_in):
                label = dict(self._fields['event']._description_selection(self.env)).get(log.event, log.event)
                Alert.ff_raise(log.employee_id, log.event, '%s: %s%s' % (
                    log.employee_id.name, label, (' - %s' % log.detail) if log.detail else ''), record=log)
        return logs


class FfVisit(models.Model):
    _inherit = 'ff.visit'

    @api.model_create_multi
    def create(self, vals_list):
        visits = super().create(vals_list)
        for visit in visits:
            if 'visit_type' in visit._fields and visit.visit_type == 'offsite':
                away = '%.1f km' % (visit.distance_m / 1000.0) if visit.distance_m >= 1000 else '%d m' % visit.distance_m
                reason = (' (%s)' % visit.offsite_reason) if visit.offsite_reason else ''
                self.env['ff.alert'].ff_raise(visit.employee_id, 'offsite_visit', '%s checked in at %s from %s away%s.' % (
                    visit.employee_id.name, visit.partner_id.display_name, away, reason), record=visit)
        return visits
