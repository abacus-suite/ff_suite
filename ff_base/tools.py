"""Shared helpers for the Field Force modules: settings, geo maths, date parsing."""
import math
from datetime import datetime, timezone

EARTH_RADIUS_M = 6371008.8

# Boolean parameters must default to False: Odoo deletes a boolean
# config parameter when it is unticked in Settings.
PARAM_DEFAULTS = {
    'ping_interval': 120,        # seconds between background pings
    'distance_filter': 50,       # metres the device must move before a ping
    'idle_threshold': 30,        # minutes without movement => inactive
    'low_battery': 20,           # percent
    'ping_retention_days': 90,
    'max_accuracy': 100,         # metres; worse pings are ignored for distance
    'allow_mock': False,
    'selfie_required': False,    # set to True by module data
    'early_checkout_reason': False,  # ask why when somebody ends the day before the shift does
    'punch_vehicle': False,      # ask how the person travels today when punching in
    'punch_odometer': False,     # ask for the odometer photo and reading at both punches
    'geofence_radius': 150,      # metres around a client counted as "at client"
    'visit_block_outside': False,  # refuse visit check-in outside the geofence
    'visit_lock': False,           # app blocks leaving a visit before check-out (data sets True)
    'visit_steps': False,          # guided step-by-step visits
    'stock_count': False,          # stock count step and history
    'payment_collection': False,   # collect money at the customer
    'idle_logout_hours': 0,        # log the app out after this long unused (0 = never)
    'max_clock_skew': 5,           # minutes a phone clock may differ from the server's
    'visit_recommendations': False,  # suggest the next visits in the app
    'recommend_radius_km': 3,      # how far to look for unplanned customers
    'recommend_due_days': 7,       # a customer is due once not visited for this long
}


def get_param(env, key):
    default = PARAM_DEFAULTS[key]
    raw = env['ir.config_parameter'].sudo().get_param('ff_base.%s' % key)
    if isinstance(default, bool):
        return raw == 'True'
    if raw in (None, False, ''):
        return default
    try:
        return int(float(raw))
    except (TypeError, ValueError):
        return default


def google_maps_key(env):
    """The Google Maps key set in Field Force settings, or '' when there is none."""
    return env['ir.config_parameter'].sudo().get_param('ff_base.google_maps_key') or ''


# How the maps are drawn, and what each way costs.
#   sdk    - Google's own map inside the phone app. Google does not charge for it.
#   google - Google tiles and Google addresses everywhere; billed by the request.
#   open   - free maps and free addresses everywhere.
#   hybrid - Google for the maps people look at, free addresses, and a guard
#            that falls back to the free maps before the free tier runs out.
MAP_MODES = ('sdk', 'google', 'open', 'hybrid')


def map_mode(env):
    """Which of the four ways this company has chosen. Defaults to the free SDK."""
    chosen = env['ir.config_parameter'].sudo().get_param('ff_base.map_mode')
    if chosen in MAP_MODES:
        return chosen
    # Databases set up before the choice existed keep what they had.
    old = env['ir.config_parameter'].sudo().get_param('ff_base.map_provider')
    if old == 'google':
        return 'hybrid'
    if old == 'open':
        return 'open'
    return 'sdk'


def map_provider(env):
    """What draws a map: 'sdk', 'google' or 'open'.

    Odoo's own web map cannot use the phone SDK, so ``sdk`` reads as ``open``
    on the web; the app asks for this with ``for_app=True``.
    """
    mode = map_mode(env)
    if mode == 'sdk':
        return 'sdk' if google_maps_key(env) else 'open'
    if mode == 'open':
        return 'open'
    if not google_maps_key(env):
        return 'open'  # Google picked but no key yet: still show a map
    return 'google' 
    return chosen


def web_map_provider(env):
    """What draws the map inside Odoo: the phone SDK is not an option here."""
    provider = map_provider(env)
    return 'open' if provider == 'sdk' else provider


def geocode_provider(env):
    """Who turns GPS points into addresses: 'open' (free OpenStreetMap, the default) or 'google'.

    Addresses are background work nobody looks at on a map, so they stay free
    even when Google draws the maps.
    """
    chosen = env['ir.config_parameter'].sudo().get_param('ff_base.geocode_provider') or 'open'
    if chosen == 'google' and google_maps_key(env) and map_mode(env) != 'open':
        return 'google'
    return 'open'


def map_style(env):
    """The free map's look: liberty (colourful), positron (light) or bright."""
    style = env['ir.config_parameter'].sudo().get_param('ff_base.open_map_style')
    return style if style in ('liberty', 'positron', 'bright') else 'liberty'


def map_link(env, latitude, longitude):
    """A link that opens a place in the chosen provider's website (free, no key)."""
    if map_provider(env) in ('google', 'sdk'):
        return 'https://www.google.com/maps?q=%s,%s' % (latitude, longitude)
    return 'https://www.openstreetmap.org/?mlat=%s&mlon=%s#map=17/%s/%s' % (latitude, longitude, latitude, longitude)


def get_settings(env):
    return {key: get_param(env, key) for key in PARAM_DEFAULTS}


def haversine_m(lat1, lng1, lat2, lng2):
    phi1, phi2 = math.radians(lat1), math.radians(lat2)
    dphi = math.radians(lat2 - lat1)
    dlmb = math.radians(lng2 - lng1)
    a = math.sin(dphi / 2) ** 2 + math.cos(phi1) * math.cos(phi2) * math.sin(dlmb / 2) ** 2
    return 2 * EARTH_RADIUS_M * math.asin(math.sqrt(a))


def path_distance_km(points, max_accuracy=100, min_step_m=15, max_speed_kmh=160):
    """Travelled distance from (ts, lat, lng, accuracy) tuples ordered by ts.

    Drops inaccurate fixes, ignores GPS jitter below ``min_step_m`` and
    rejects jumps implying an impossible speed.
    """
    total = 0.0
    last = None
    for ts, lat, lng, accuracy in points:
        if accuracy and accuracy > max_accuracy:
            continue
        if last is None:
            last = (ts, lat, lng)
            continue
        step = haversine_m(last[1], last[2], lat, lng)
        if step < min_step_m:
            continue
        seconds = (ts - last[0]).total_seconds()
        if seconds > 0 and step / seconds * 3.6 > max_speed_kmh:
            continue
        total += step
        last = (ts, lat, lng)
    return round(total / 1000.0, 3)


def parse_client_dt(value):
    """ISO 8601 string or epoch (s or ms) -> naive UTC datetime (Odoo format)."""
    if value in (None, False, ''):
        return None
    if isinstance(value, (int, float)):
        seconds = value / 1000.0 if value > 1e11 else value
        return datetime.fromtimestamp(seconds, tz=timezone.utc).replace(tzinfo=None)
    dt = datetime.fromisoformat(str(value).strip().replace('Z', '+00:00'))
    if dt.tzinfo:
        dt = dt.astimezone(timezone.utc).replace(tzinfo=None)
    return dt


# How far back a queued offline action may be dated.
OFFLINE_MAX_AGE_DAYS = 7


def client_time(data):
    """When an action really happened: ``data['at']`` for work queued offline, else now.

    A device clock ahead of the server is clamped to now; anything older than
    OFFLINE_MAX_AGE_DAYS is refused rather than silently back-dated.
    Returns (naive UTC datetime, is_offline).
    """
    from datetime import timedelta

    now = datetime.now(timezone.utc).replace(tzinfo=None, microsecond=0)
    at = parse_client_dt((data or {}).get('at'))
    if not at:
        return now, False
    if at > now:
        return now, True
    if now - at > timedelta(days=OFFLINE_MAX_AGE_DAYS):
        raise ValueError('This was recorded more than %d days ago and can no longer be synced.'
                         % OFFLINE_MAX_AGE_DAYS)
    return at.replace(microsecond=0), True


def clock_skew_minutes(data):
    """How far the phone's clock (``data['device_time']``) is from the server's, in minutes; None if not sent."""
    device = parse_client_dt((data or {}).get('device_time'))
    if not device:
        return None
    now = datetime.now(timezone.utc).replace(tzinfo=None)
    return abs((device - now).total_seconds()) / 60.0


def to_iso(value):
    """Odoo naive-UTC datetime (or date) -> ISO string for the API."""
    if not value:
        return None
    if isinstance(value, datetime):
        return value.replace(tzinfo=timezone.utc).isoformat().replace('+00:00', 'Z')
    return value.isoformat()
