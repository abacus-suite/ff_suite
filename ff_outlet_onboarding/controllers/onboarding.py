"""Onboarding a lead from the app."""
from odoo import http
from odoo.exceptions import UserError
from odoo.http import request

from odoo.addons.ff_mobile_api.controllers.clients import to_int, visible_client
from odoo.addons.ff_mobile_api.controllers.common import ApiError, api_route, body, ok
from odoo.addons.ff_mobile_api.controllers.field_data import client_data


class FieldForceOnboardingApi(http.Controller):

    @api_route('/api/v1/onboarding/options', methods=('GET',))
    def options(self, employee, **kw):
        return ok(request.env['res.partner'].ff_onboarding_options())

    @api_route('/api/v1/clients/<int:partner_id>/onboard', methods=('POST',))
    def onboard(self, employee, partner_id, **kw):
        partner = visible_client(employee, partner_id)
        data = body()
        try:
            partner = partner.ff_onboard(employee, data.get('kind'), data)
        except UserError as error:
            request.env.cr.rollback()
            raise ApiError(str(error), 400, 'invalid')
        return ok(client_data(partner))
