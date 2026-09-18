"""The app tells Odoo how many Google tiles it fetched, so the bill is visible."""
from odoo import http
from odoo.http import request

from odoo.addons.ff_mobile_api.controllers.common import api_route, body, ok


class FieldForceMapUsageApi(http.Controller):

    @api_route('/api/v1/maps/usage', methods=('POST',))
    def usage(self, employee, **kw):
        data = body()
        Usage = request.env['ff.map.usage']
        Usage.ff_record('tiles', data.get('tiles'), employee=employee)
        Usage.ff_record('session', data.get('sessions'), employee=employee)
        # Tells the app whether Google tiles are still within this month's free tier.
        return ok({'recorded': True, 'google': Usage.ff_google_allowed('tiles')})
