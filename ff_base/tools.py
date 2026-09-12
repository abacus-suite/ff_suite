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
    'geofence_radius': 150,      # metres around a client counted as "at client"
    'visit_block_outside': False,  # refuse visit check-in outside the geofence
    'visit_lock': False,           # app blocks leaving a visit before check-out (data sets True)
    'visit_steps': False,          # guided step-by-step visits
    'stock_count': False,          # stock count step and history
    'payment_collection': False,   # collect money at the customer
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


def to_iso(value):
    """Odoo naive-UTC datetime (or date) -> ISO string for the API."""
    if not value:
        return None
    if isinstance(value, datetime):
        return value.replace(tzinfo=timezone.utc).isoformat().replace('+00:00', 'Z')
    return value.isoformat()
