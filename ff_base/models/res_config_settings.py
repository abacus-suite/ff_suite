from odoo import fields, models


class ResConfigSettings(models.TransientModel):
    _inherit = 'res.config.settings'

    ff_ping_interval = fields.Integer(
        string='Ping Interval (sec)', config_parameter='ff_base.ping_interval', default=120)
    ff_distance_filter = fields.Integer(
        string='Distance Filter (m)', config_parameter='ff_base.distance_filter', default=50)
    ff_idle_threshold = fields.Integer(
        string='Inactive After (min)', config_parameter='ff_base.idle_threshold', default=30)
    ff_low_battery = fields.Integer(
        string='Low Battery (%)', config_parameter='ff_base.low_battery', default=20)
    ff_max_accuracy = fields.Integer(
        string='Max GPS Accuracy (m)', config_parameter='ff_base.max_accuracy', default=100)
    ff_ping_retention_days = fields.Integer(
        string='Keep Raw Pings (days)', config_parameter='ff_base.ping_retention_days', default=90)
    ff_allow_mock = fields.Boolean(
        string='Allow Mock Locations', config_parameter='ff_base.allow_mock')
    ff_selfie_required = fields.Boolean(
        string='Selfie Required on Punch', config_parameter='ff_base.selfie_required')
