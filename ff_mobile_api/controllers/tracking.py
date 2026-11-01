from odoo import fields, http
from odoo.http import request

from odoo.addons.ff_base.tools import get_param, haversine_m, path_distance_km, to_iso

from .common import ApiError, api_route, body, ok

MAX_BATCH = 500
MAX_DAY_POINTS = 300


def _batch(key):
    items = body().get(key)
    if not isinstance(items, list) or not items:
        raise ApiError('"%s" must be a non-empty list.' % key)
    if len(items) > MAX_BATCH:
        raise ApiError('At most %s items per request.' % MAX_BATCH)
    return items


class FieldForceTrackingApi(http.Controller):

    @api_route('/api/v1/tracking/pings', methods=('POST',))
    def pings(self, employee, **kw):
        if not employee.ff_tracking_enabled:
            return ok({'accepted': 0, 'duplicates': 0, 'rejected': 0, 'tracking_enabled': False})
        result = request.env['ff.location.ping'].ff_ingest(employee, _batch('pings'))
        return ok(dict(result, tracking_enabled=True))

    @api_route('/api/v1/tracking/compliance', methods=('POST',))
    def compliance(self, employee, **kw):
        return ok(request.env['ff.compliance.log'].ff_log(employee, _batch('events')))

    @api_route('/api/v1/tracking/my-day', methods=('GET',))
    def my_day(self, employee, date=None, **kw):
        """Own travelled distance and route of a day (for the home dashboard map)."""
        try:
            day = fields.Date.to_date(date) if date else employee._ff_today()
        except ValueError:
            raise ApiError('date must be YYYY-MM-DD.')
        start, end = employee._ff_day_bounds(day)
        all_pings = request.env['ff.location.ping'].sudo().search([
            ('employee_id', '=', employee.id), ('ts', '>=', start), ('ts', '<', end), ('is_mock', '=', False),
        ], order='ts asc')
        # Only the time on duty counts: pings from before the person checked in, or between
        # check-outs, are not travel.
        now = fields.Datetime.now()
        shifts = request.env['hr.attendance'].sudo().search([
            ('employee_id', '=', employee.id), ('check_in', '<', end),
            '|', ('check_out', '=', False), ('check_out', '>=', start),
        ])
        windows = [(att.check_in, att.check_out or now) for att in shifts]
        pings = all_pings.filtered(lambda p: any(low <= p.ts <= high for low, high in windows)) \
            if windows else all_pings.browse()
        step = len(pings) // MAX_DAY_POINTS + 1
        sampled = pings[::step]
        if pings and sampled[-1] != pings[-1]:
            sampled |= pings[-1]
        accuracy = get_param(request.env, 'max_accuracy')
        distance = path_distance_km([(p.ts, p.latitude, p.longitude, p.accuracy) for p in pings], max_accuracy=accuracy)
        # Time spent moving: the gaps between fixes in which the person actually went somewhere.
        moving = 0.0
        previous = None
        for ping in pings:
            if accuracy and ping.accuracy and ping.accuracy > accuracy:
                continue
            if previous is not None:
                seconds = (ping.ts - previous.ts).total_seconds()
                metres = haversine_m(previous.latitude, previous.longitude, ping.latitude, ping.longitude)
                if 0 < seconds <= 900 and metres >= 30 and metres / seconds * 3.6 >= 2:
                    moving += seconds
            previous = ping
        # For a bike or a car the meter is the final word: out minus in, summed over the day's punches.
        odometer_km = round(sum(shifts.filtered(lambda att: att.check_in >= start).mapped('ff_odometer_km')), 1)
        return ok({
            'date': day.isoformat(),
            'odometer_km': odometer_km or None,
            'distance_km': distance,
            'travel_minutes': int(round(moving / 60.0)),
            'points': [{'ts': to_iso(p.ts), 'lat': p.latitude, 'lng': p.longitude} for p in sampled],
        })
