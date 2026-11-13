"""Onboarding a lead from the app."""
import logging
import re

import requests

from odoo import http
from odoo.exceptions import UserError
from odoo.http import request

from odoo.addons.ff_mobile_api.controllers.clients import to_int, visible_client
from odoo.addons.ff_mobile_api.controllers.common import ApiError, api_route, body, ok
from odoo.addons.ff_mobile_api.controllers.field_data import client_data


_logger = logging.getLogger(__name__)

GSTIN_RE = re.compile(r'^[0-9]{2}[A-Z]{5}[0-9]{4}[A-Z][1-9A-Z]Z[0-9A-Z]$')
GST_CHARS = '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ'
# The first two digits of a GSTIN name the state.
GST_STATES = {
    '01': 'Jammu and Kashmir', '02': 'Himachal Pradesh', '03': 'Punjab', '04': 'Chandigarh', '05': 'Uttarakhand',
    '06': 'Haryana', '07': 'Delhi', '08': 'Rajasthan', '09': 'Uttar Pradesh', '10': 'Bihar', '11': 'Sikkim',
    '12': 'Arunachal Pradesh', '13': 'Nagaland', '14': 'Manipur', '15': 'Mizoram', '16': 'Tripura',
    '17': 'Meghalaya', '18': 'Assam', '19': 'West Bengal', '20': 'Jharkhand', '21': 'Odisha',
    '22': 'Chhattisgarh', '23': 'Madhya Pradesh', '24': 'Gujarat', '26': 'Dadra and Nagar Haveli and Daman and Diu',
    '27': 'Maharashtra', '29': 'Karnataka', '30': 'Goa', '31': 'Lakshadweep', '32': 'Kerala', '33': 'Tamil Nadu',
    '34': 'Puducherry', '35': 'Andaman and Nicobar Islands', '36': 'Telangana', '37': 'Andhra Pradesh',
    '38': 'Ladakh',
}


def gstin_check_digit_ok(gstin):
    """The 15th character of a GSTIN is a check digit of the other fourteen."""
    total = 0
    for index, char in enumerate(gstin[:14]):
        value = GST_CHARS.index(char) * (1 if index % 2 == 0 else 2)
        total += value // 36 + value % 36
    return GST_CHARS[(36 - total % 36) % 36] == gstin[14]


class FieldForceOnboardingApi(http.Controller):

    @api_route('/api/v1/gst/check', methods=('GET',))
    def gst_check(self, employee, gstin=None, **kw):
        """Is this a real-looking GSTIN, and which state and PAN does it carry? (Free: no outside service.)"""
        text = (gstin or '').strip().upper()
        if not GSTIN_RE.match(text):
            return ok({'valid': False, 'reason': 'A GSTIN has 15 characters, for example 32ABCDE1234F1Z5.'})
        name = GST_STATES.get(text[:2])
        result = {'valid': True, 'pan': text[2:12], 'state': name}
        if not gstin_check_digit_ok(text):
            # A warning, not a refusal: the person may be right and the check wrong, and the office verifies GSTINs.
            result['warning'] = 'The check digit does not match. Please re-check the GSTIN.'
        return ok(result)

    @api_route('/api/v1/gst/verify', methods=('GET',))
    def gst_verify(self, employee, gstin=None, **kw):
        """Look a GSTIN up with the GST service the office has set up (System Parameters ``ff_base.gst_api_url`` and
        ``ff_base.gst_api_key``): the registered name, PIN code and address, to fill the onboarding form."""
        text = (gstin or '').strip().upper()
        if not GSTIN_RE.match(text):
            raise ApiError('Enter a valid 15-character GSTIN first.')
        params = request.env['ir.config_parameter'].sudo()
        url = (params.get_param('ff_base.gst_api_url') or '').strip()
        key = (params.get_param('ff_base.gst_api_key') or '').strip()
        if not url:
            raise ApiError('GST verification is not set up yet: the office has to add the GST service URL and key '
                           '(ff_base.gst_api_url, ff_base.gst_api_key).')
        try:
            reply = requests.get(url.replace('{gstin}', text) if '{gstin}' in url else url,
                                 params=None if '{gstin}' in url else {'gstin': text},
                                 headers={'Authorization': key, 'X-API-Key': key} if key else {}, timeout=12)
            payload = reply.json()
        except (requests.RequestException, ValueError) as error:
            _logger.warning('Field Force: GST lookup failed (%s)', error)
            raise ApiError('The GST service could not be reached. Try again, or type the details.')
        data = payload.get('data') if isinstance(payload.get('data'), dict) else payload
        address = ((data.get('pradr') or {}).get('addr') or {}) if isinstance(data.get('pradr'), dict) else {}
        street = ', '.join(x for x in (address.get('bno'), address.get('bnm'), address.get('st'), address.get('loc'),
                                       address.get('dst'), address.get('stcd')) if x)
        name = data.get('tradeNam') or data.get('lgnm') or data.get('legal_name') or data.get('trade_name')
        pin = address.get('pncd') or data.get('pincode') or data.get('pinCode') or ''
        if not (name or street):
            raise ApiError(payload.get('message') or 'This GSTIN was not found.')
        return ok({'name': name, 'legal_name': data.get('lgnm') or data.get('legal_name'),
                   'pin': str(pin or ''), 'address': street or data.get('address') or '',
                   'door': ', '.join(x for x in (address.get('bno'), address.get('bnm')) if x)})

    @api_route('/api/v1/geo/pincode', methods=('GET',))
    def pincode(self, employee, pin=None, **kw):
        """State, district and the places of a PIN code, from India Post's free lookup. Empty when it cannot say."""
        code = (pin or '').strip()
        if not re.fullmatch(r'[0-9]{6}', code):
            raise ApiError('A PIN code has 6 digits.')
        try:
            payload = requests.get('https://api.postalpincode.in/pincode/%s' % code, timeout=6).json()
        except (requests.RequestException, ValueError) as error:
            _logger.warning('Field Force: PIN lookup failed (%s)', error)
            return ok({'found': False})
        offices = ((payload[0] if isinstance(payload, list) and payload else {}).get('PostOffice')) or []
        if not offices:
            return ok({'found': False})

        def unique(values):
            seen, out = set(), []
            for value in values:
                value = (value or '').strip()
                if value and value.lower() not in seen:
                    seen.add(value.lower())
                    out.append(value)
            return sorted(out, key=str.lower)

        return ok({
            'found': True,
            'state': offices[0].get('State'),
            'district': offices[0].get('District'),
            # The towns and the post-office areas to choose from.
            'cities': unique([o.get('Block') for o in offices] + [offices[0].get('District')]),
            'areas': unique([o.get('Name') for o in offices]),
        })

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
