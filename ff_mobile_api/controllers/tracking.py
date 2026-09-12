from odoo import fields, http
from odoo.http import request

from odoo.addons.ff_base.tools import to_iso

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
        pings = request.env['ff.location.ping'].sudo().search([
            ('employee_id', '=', employee.id), ('ts', '>=', start), ('ts', '<', end), ('is_mock', '=', False),
        ], order='ts asc')
        step = len(pings) // MAX_DAY_POINTS + 1
        sampled = pings[::step]
        if pings and sampled[-1] != pings[-1]:
            sampled |= pings[-1]
        track = request.env['ff.daily.track']._ff_compute(employee, day)
        return ok({
            'date': day.isoformat(),
            'distance_km': track.distance_km if track else 0.0,
            'points': [{'ts': to_iso(p.ts), 'lat': p.latitude, 'lng': p.longitude} for p in sampled],
        })
