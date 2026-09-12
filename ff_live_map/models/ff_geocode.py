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
            self._ff_note_problem('No Google Maps key is set in Field Force settings.')
            return self
        pending = self._ff_needs_address()[:BATCH]
        for status in pending:
            address = self._ff_reverse_geocode(status.latitude, status.longitude, key)
            if not address:
                continue
            self._ff_note_problem(False)
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
            })
            payload = response.json()
        except (requests.RequestException, ValueError) as error:
            _logger.warning('Field Force: reverse geocoding failed (%s)', error)
            self._ff_note_problem('Google could not be reached: %s' % error)
            return False
        if payload.get('status') != 'OK' or not payload.get('results'):
            problem = payload.get('status') or 'no answer'
            if payload.get('error_message'):
                problem = '%s - %s' % (problem, payload['error_message'])
            if payload.get('status') != 'ZERO_RESULTS':
                _logger.warning('Field Force: Google geocoding said %s', problem)
                self._ff_note_problem(problem)
            return False
        return self._ff_short_address(payload['results'][0])

    def _ff_short_address(self, result):
        """A readable place, not the postal essay Google returns.

        Field managers recognise "Nallalam, Kozhikode": the neighbourhood and
        the town. The full address is kept when those parts are missing.
        """
        wanted = ('sublocality', 'sublocality_level_1', 'neighborhood', 'locality',
                  'administrative_area_level_3', 'administrative_area_level_2')
        parts = []
        for component in result.get('address_components', []):
            for kind in component.get('types', []):
                if kind in wanted and component['long_name'] not in parts:
                    parts.append(component['long_name'])
                    break
            if len(parts) >= 3:
                break
        route = next((c['long_name'] for c in result.get('address_components', [])
                      if 'route' in c.get('types', [])), '')
        if route:
            parts.insert(0, route)
        return ', '.join(parts[:3]) or result.get('formatted_address') or False

    def _ff_note_problem(self, message):
        """Keep the last geocoding problem so the panel can show it."""
        self.env['ir.config_parameter'].sudo().set_param('ff_base.geocode_problem', message or '')
