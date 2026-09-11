from odoo import http
from odoo.http import request

from .common import ApiError, api_route, body, ok

MAX_BATCH = 500


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
