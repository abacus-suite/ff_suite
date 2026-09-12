"""Turn the last GPS fix into a street address people can read.

Google charges per lookup, so an address is fetched only when the person has
actually moved away from where it was resolved, and it is cached on the status
row. Everything is best-effort: no key, no network or a refused key simply
leaves the coordinates showing.
"""
import logging

import requests

from odoo import fields, models

from odoo.addons.ff_base.tools import google_maps_key, haversine_m

_logger = logging.getLogger(__name__)

GEOCODE_URL = 'https://maps.googleapis.com/maps/api/geocode/json'
# How far somebody must move before the cached address is considered stale.
MOVED_M = 150
# Never resolve more than this many people in one screen refresh.
BATCH = 12
TIMEOUT = 5


class FfEmployeeStatusGeocode(models.Model):
    _inherit = 'ff.employee.status'

    address = fields.Char(string='Last Address', readonly=True)
    address_at = fields.Datetime(string='Address Resolved', readonly=True)
    address_latitude = fields.Float(digits=(10, 7), readonly=True)
    address_longitude = fields.Float(digits=(10, 7), readonly=True)

    def _ff_needs_address(self):
        """Rows whose cached address no longer describes where they are."""
        needing = self.browse()
        for status in self:
            if not status.latitude and not status.longitude:
                continue
            if not status.address:
                needing |= status
            elif haversine_m(status.address_latitude, status.address_longitude,
                             status.latitude, status.longitude) > MOVED_M:
                needing |= status
        return needing

    def ff_resolve_addresses(self):
        """Fill in missing addresses, within the batch limit. Returns self."""
        key = google_maps_key(self.env)
        if not key:
            return self
        pending = self._ff_needs_address()[:BATCH]
        for status in pending:
            address = self._ff_reverse_geocode(status.latitude, status.longitude, key)
            if not address:
                continue
            status.sudo().write({
                'address': address,
                'address_at': fields.Datetime.now(),
                'address_latitude': status.latitude,
                'address_longitude': status.longitude,
            })
            self.env['ff.map.usage'].ff_record('geocode', 1, employee=status.employee_id)
        return self

    def _ff_reverse_geocode(self, latitude, longitude, key):
        try:
            response = requests.get(GEOCODE_URL, timeout=TIMEOUT, params={
                'latlng': '%s,%s' % (latitude, longitude),
                'key': key,
                'result_type': 'street_address|premise|route|sublocality|locality',
            })
            payload = response.json()
        except (requests.RequestException, ValueError) as error:
            _logger.warning('Field Force: reverse geocoding failed (%s)', error)
            return False
        if payload.get('status') != 'OK' or not payload.get('results'):
            if payload.get('status') not in ('ZERO_RESULTS', 'OK'):
                _logger.warning('Field Force: Google geocoding said %s - %s',
                                payload.get('status'), payload.get('error_message', ''))
            return False
        return payload['results'][0].get('formatted_address') or False
