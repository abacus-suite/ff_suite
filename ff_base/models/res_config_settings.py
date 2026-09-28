from odoo import fields, models
from odoo.addons.base.models.res_partner import _tz_get


class ResConfigSettings(models.TransientModel):
    _inherit = 'res.config.settings'

    ff_default_tz = fields.Selection(
        _tz_get, string='Field Timezone', config_parameter='ff_base.default_tz',
        help='Used wherever an employee or user has no timezone (or only the UTC default), '
             'so "today" and every punch time match the local day.')
    ff_idle_logout_hours = fields.Integer(
        string='Log Out Unused App After (hours)', config_parameter='ff_base.idle_logout_hours', default=0,
        help='The app asks for the password again after this long without being opened. 0 = never.')
    ff_max_clock_skew = fields.Integer(
        string='Allowed Phone Clock Difference (min)', config_parameter='ff_base.max_clock_skew', default=5,
        help='A punch or check-in from a phone whose clock is further off than this is refused and logged.')
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
    ff_early_checkout_reason = fields.Boolean(
        string='Reason for an Early Check-out', config_parameter='ff_base.early_checkout_reason',
        help='Somebody checking out before their shift ends must say why. The reason is kept on the attendance.')
    ff_duty_check_minutes = fields.Integer(
        string='Ask "Still Working?" Every (min)', config_parameter='ff_base.duty_check_minutes', default=30,
        help='While somebody is checked in the app asks whether they are still working. '
             '0 = never ask.')
    ff_duty_reply_minutes = fields.Integer(
        string='Wait for the Answer (min)', config_parameter='ff_base.duty_reply_minutes', default=5,
        help='No answer in this time and the app checks them out by itself, at the moment they were last seen.')
    ff_close_day_at_midnight = fields.Boolean(
        string='Close a Forgotten Day at Midnight', config_parameter='ff_base.close_day_at_midnight',
        default=True,
        help='A day left open is closed at the end of it, so tomorrow starts clean instead of '
             'running one punch across two days.')
    ff_single_punch_day = fields.Boolean(
        string='One Check-in per Day', config_parameter='ff_base.single_punch_day',
        help='Once somebody has checked out, they cannot check in again that day. '
             'Leave it off to let people check in and out as often as they need; the day is still '
             'counted once, with the hours added up.')
    ff_punch_vehicle = fields.Boolean(
        string='Ask the Vehicle on Punch-in', config_parameter='ff_base.punch_vehicle',
        help='At check-in the app asks how the person is travelling today (two-wheeler, car, public transport, on foot). '
             'It is kept on the attendance and used for the travel allowance.')
    ff_punch_odometer = fields.Boolean(
        string='Odometer Photo on Punch', config_parameter='ff_base.punch_odometer',
        help='At check-in and check-out the app asks for a photo of the odometer and the reading on it. '
             'The photo carries the place and time, and the day\'s kilometres are worked out from the two readings.')
    ff_api_log = fields.Boolean(
        string='Log App Requests', config_parameter='ff_base.api_log',
        help='Writes every request the app makes, and the size of each answer, to the server log. '
             'Photos, tokens and passwords are never written. Leave it off except while looking '
             'into a problem: the log grows quickly.')
    ff_contact_access = fields.Selection(
        [('scoped', 'Only their own contacts and their team\'s'),
         ('open', 'Every beat and every contact on a beat')],
        string='Who Sees Which Contacts', config_parameter='ff_base.contact_access', default='scoped',
        help='Open access suits a team that shares outlets: everybody sees every beat and every contact '
             'on one, and the same shop can be visited by more than one person on the same day. '
             'Leads stay private to whoever added them and to their managers, either way.')
    ff_beat_required = fields.Boolean(
        string='Beat Required for Outlets and Distributors', config_parameter='ff_base.beat_required',
        default=True,
        help='An outlet or a distributor must sit on a beat. A lead may be added without one and gets '
             'its beat when it becomes a real customer.')
    ff_geofence_radius = fields.Integer(
        string='Client Geofence (m)', config_parameter='ff_base.geofence_radius', default=150)
    ff_visit_block_outside = fields.Boolean(
        string='Block Check-in Outside Geofence', config_parameter='ff_base.visit_block_outside')
    ff_auto_visit = fields.Boolean(
        string='Check In on Arrival', config_parameter='ff_base.auto_visit',
        help='Reaching a customer inside its geofence starts the visit by itself, and walking away '
             'closes it. A visit started by hand away from the shop is never closed this way.')
    ff_auto_visit_exit_m = fields.Integer(
        string='Counts as Left After (m)', config_parameter='ff_base.auto_visit_exit_m', default=60,
        help='Metres beyond the geofence before the app treats the person as having left.')
    ff_auto_visit_leave_secs = fields.Integer(
        string='Away For (seconds)', config_parameter='ff_base.auto_visit_leave_secs', default=90,
        help='How long they must stay away before the visit closes by itself. It keeps a walk to the '
             'car or a weak GPS fix from ending the visit.')
    ff_visit_lock = fields.Boolean(
        string='Lock the Visit Until Check-out', config_parameter='ff_base.visit_lock',
        help='In the app, field staff cannot leave the visit screen before checking out.')
    ff_visit_steps = fields.Boolean(
        string='Guided Visit Steps', config_parameter='ff_base.visit_steps',
        help='Show configured steps (notes, photo, stock count, order...) during a visit.')
    ff_stock_count = fields.Boolean(
        string='Stock Count', config_parameter='ff_base.stock_count',
        help='Count stock at the customer and compare it with the previous count.')
    ff_visit_recommendations = fields.Boolean(
        string='Visit Recommendations', config_parameter='ff_base.visit_recommendations',
        help='In the app, suggest the shortest order for the planned customers of the day and nearby customers due a visit.')
    ff_recommend_radius_km = fields.Integer(string='Look Nearby Within (km)', config_parameter='ff_base.recommend_radius_km',
                                            default=3)
    ff_recommend_due_days = fields.Integer(string='Due After (days)', config_parameter='ff_base.recommend_due_days',
                                           default=7)
    ff_payment_collection = fields.Boolean(
        string='Payment Collection', config_parameter='ff_base.payment_collection',
        help='Collect money at the customer and deposit it to the office.')
    ff_map_mode = fields.Selection(
        [('sdk', "Google map inside the app (free, needs a key)"),
         ('google', 'Google everywhere (billed by request)'),
         ('open', 'Open maps everywhere (free, no key)'),
         ('hybrid', 'Google for maps, free addresses (billed by request)')],
        string='Maps', config_parameter='ff_base.map_mode', default='sdk',
        help="Google map inside the app: the phone draws Google's own map, which Google does not charge for; "
             "Odoo's web map uses the free map. Google everywhere: Google tiles, web map and addresses, all billed. "
             "Open maps: free everywhere, no key. Google for maps, free addresses: Google draws the maps people "
             "look at, addresses stay free, and the guard switches to free maps before the free tier runs out.")
    ff_geocode_provider = fields.Selection(
        [('open', 'OpenStreetMap (free)'), ('google', 'Google Geocoding (paid after the free tier)')],
        string='Address Lookups', config_parameter='ff_base.geocode_provider', default='open',
        help='Turning GPS points into street addresses runs in the background, so it can stay free '
             'even when Google draws the maps.')
    ff_map_provider = fields.Selection(
        [('google', 'Google'), ('open', 'Open maps')],
        string='Map Provider (old)', config_parameter='ff_base.map_provider',
        help='Kept so databases set up before the four choices existed still read correctly.')
    ff_open_map_style = fields.Selection(
        [('liberty', 'Liberty (colourful)'), ('positron', 'Positron (light)'), ('bright', 'Bright')],
        string='Free Map Style', config_parameter='ff_base.open_map_style', default='liberty')
    ff_google_maps_key = fields.Char(
        string='Google Maps API Key', config_parameter='ff_base.google_maps_key',
        help='Key from your Google Cloud project. Odoo uses it for the live map; the app receives '
             'it at login and uses it for its maps. Leave empty to use the free OpenStreetMap basemap.')

    def action_ff_apply_timezone(self):
        """Give the field timezone to every employee and user still on UTC or none."""
        self.ensure_one()
        tz = self.ff_default_tz or self.env['ir.config_parameter'].sudo().get_param('ff_base.default_tz')
        if not tz:
            return False
        employees = self.env['hr.employee'].sudo().search(['|', ('tz', '=', False), ('tz', '=', 'UTC')])
        employees.write({'tz': tz})
        users = self.env['res.users'].sudo().search([('share', '=', False), '|', ('tz', '=', False), ('tz', '=', 'UTC')])
        users.write({'tz': tz})
        return {
            'type': 'ir.actions.client', 'tag': 'display_notification',
            'params': {'type': 'success', 'sticky': False,
                       'message': self.env._('Timezone set on %(e)s employees and %(u)s users.',
                                             e=len(employees), u=len(users))},
        }
