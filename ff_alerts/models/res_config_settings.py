from odoo import api, fields, models

# Switches that default to on. Odoo removes a boolean config parameter when it
# is unticked, which would read back as "on" again - so these are stored by
# hand as the words True / False.
SWITCHES = {
    'ff_alerts_enabled': 'enabled',
    'ff_alerts_kind_inactive': 'kind_inactive',
    'ff_alerts_kind_no_signal': 'kind_no_signal',
    'ff_alerts_kind_gps_off': 'kind_gps_off',
    'ff_alerts_kind_offsite_visit': 'kind_offsite_visit',
    'ff_alerts_kind_mock_location': 'kind_mock_location',
    'ff_digest_daily': 'digest_daily',
    'ff_digest_weekly': 'digest_weekly',
}


class ResConfigSettings(models.TransientModel):
    _inherit = 'res.config.settings'

    ff_alerts_enabled = fields.Boolean(string='Alert Managers')
    ff_alerts_repeat_minutes = fields.Integer(
        string='Repeat the Same Alert After (min)', config_parameter='ff_alerts.repeat_minutes', default=60)
    ff_alerts_kind_inactive = fields.Boolean(string='Not moving')
    ff_alerts_kind_no_signal = fields.Boolean(string='No signal')
    ff_alerts_kind_gps_off = fields.Boolean(string='GPS off / location permission removed')
    ff_alerts_kind_offsite_visit = fields.Boolean(string='Offsite visits')
    ff_alerts_kind_mock_location = fields.Boolean(string='Fake GPS / phone clock changed')

    ff_digest_daily = fields.Boolean(string='Daily Email Summary')
    ff_digest_weekly = fields.Boolean(string='Weekly Email Summary')
    ff_digest_hour = fields.Integer(string='Send At (hour, 0-23)', config_parameter='ff_alerts.digest_hour', default=20)

    @api.model
    def get_values(self):
        values = super().get_values()
        Param = self.env['ir.config_parameter'].sudo()
        for field, key in SWITCHES.items():
            values[field] = Param.get_param('ff_alerts.%s' % key, 'True') != 'False'
        return values

    def set_values(self):
        super().set_values()
        Param = self.env['ir.config_parameter'].sudo()
        for field, key in SWITCHES.items():
            Param.set_param('ff_alerts.%s' % key, 'True' if self[field] else 'False')
        # One switch each covers the related kinds.
        Param.set_param('ff_alerts.kind_time_tampered', 'True' if self.ff_alerts_kind_mock_location else 'False')
        Param.set_param('ff_alerts.kind_permission_revoked', 'True' if self.ff_alerts_kind_gps_off else 'False')

    def action_ff_send_digest_now(self):
        count = self.env['ff.digest'].ff_send_now()
        return {'type': 'ir.actions.client', 'tag': 'display_notification',
                'params': {'type': 'success', 'message': self.env._('Summary emailed to %s managers.', count)}}
