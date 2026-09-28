"""The app tells Odoo how many Google tiles it fetched, so the bill is visible."""
from odoo import http
from odoo.http import request

from odoo.addons.ff_mobile_api.controllers.common import ApiError, api_route, body, ok


class FieldForceMapUsageApi(http.Controller):

    @api_route('/api/v1/geo/address', methods=('GET',))
    def address(self, employee, lat=None, lng=None, **kw):
        """The place at a point, so the app can stamp photos with it."""
        try:
            latitude, longitude = float(lat), float(lng)
        except (TypeError, ValueError):
            raise ApiError('lat and lng are required.')
        return ok({'address': request.env['ff.employee.status'].ff_address_at(latitude, longitude)})

    @api_route('/api/v1/maps/usage', methods=('POST',))
    def usage(self, employee, **kw):
        data = body()
        Usage = request.env['ff.map.usage']
        Usage.ff_record('tiles', data.get('tiles'), employee=employee)
        Usage.ff_record('session', data.get('sessions'), employee=employee)
        # Tells the app whether Google tiles are still within this month's free tier.
        return ok({'recorded': True, 'google': Usage.ff_google_allowed('tiles')})
