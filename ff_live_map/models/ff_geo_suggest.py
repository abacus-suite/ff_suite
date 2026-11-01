"""Suggest the district, territory and area of a new contact from where it stands.

Territory and area come from the contacts already around that point: the few nearest ones, within a short
distance, vote. The city and district come from the same neighbours when there are any, and from an address
lookup when there are not. The lookup uses Google only while this month's free allowance lasts (the same guard
the maps use) and the free OpenStreetMap after that, so it never becomes a bill.
"""
import logging
import math
from collections import Counter

import requests

from odoo import api, models

from odoo.addons.ff_base.tools import geocode_provider, google_maps_key, haversine_m

from .ff_geocode import GEOCODE_URL, NOMINATIM_URL, TIMEOUT

_logger = logging.getLogger(__name__)

# Contacts nearer than this to the new one decide its territory and area; the nearest few of them vote.
NEAR_M = 1500
VOTERS = 5


def _ref(record):
    return {'id': record.id, 'name': record.name} if record else None


class FfGeoSuggest(models.AbstractModel):
    _name = 'ff.geo.suggest'
    _description = 'Place Suggestion From a GPS Point'

    @api.model
    def ff_suggest(self, employee, latitude, longitude):
        """What the app fills in: {district, territory, area, city, source, provider}, each None when unknown."""
        place = self._ff_from_contacts(latitude, longitude)
        result = {
            'district': place.get('district'), 'territory': place.get('territory'), 'area': place.get('area'),
            'city': (place.get('district') or {}).get('name'), 'source': 'contacts' if place else None,
            'provider': None,
        }
        if not result['district']:
            names, provider = self._ff_lookup(employee, latitude, longitude)
            district = self._ff_match_district(names)
            if names or district:
                result['city'] = names[0] if names else district.name
                result['district'] = _ref(district)
                result['source'] = result['source'] or 'lookup'
                result['provider'] = provider
        return result

    # ------------------------------------------------------------------ from the contacts around
    @api.model
    def _ff_from_contacts(self, latitude, longitude):
        Partner = self.env['res.partner'].sudo()
        step = NEAR_M / 111000.0
        step_lng = step / max(math.cos(math.radians(latitude)), 0.2)
        found = Partner.search([
            ('ff_is_client', '=', True), ('active', '=', True),
            ('partner_latitude', '>=', latitude - step), ('partner_latitude', '<=', latitude + step),
            ('partner_longitude', '>=', longitude - step_lng), ('partner_longitude', '<=', longitude + step_lng),
        ], limit=300)
        ranked = sorted(
            ((haversine_m(latitude, longitude, p.partner_latitude, p.partner_longitude), p) for p in found),
            key=lambda row: row[0])
        voters = [p for metres, p in ranked if metres <= NEAR_M][:VOTERS]
        if not voters:
            return {}

        def top(records):
            records = [r for r in records if r]
            return Counter(records).most_common(1)[0][0] if records else None

        territory = top([p.ff_territory_id for p in voters]) if 'ff_territory_id' in Partner._fields else None
        # The area of the voters that agree on the territory, else of any.
        pool = [p for p in voters if not territory or p.ff_territory_id == territory] if territory else voters
        area = top([p.ff_area_id for p in pool]) if 'ff_area_id' in Partner._fields else None
        district = top([p.ff_district_id for p in voters])
        place = {}
        if territory:
            place['territory'] = _ref(territory)
        if area:
            place['area'] = _ref(area)
        if district:
            place['district'] = _ref(district)
        return place

    # ------------------------------------------------------------------ from an address lookup
    @api.model
    def _ff_lookup(self, employee, latitude, longitude):
        """Place names around the point, the most local first, and who gave them ('google' or 'open')."""
        Usage = self.env['ff.map.usage']
        if geocode_provider(self.env) == 'google' and Usage.ff_google_allowed('geocode'):
            names, billed = self._ff_google_names(latitude, longitude)
            if billed:
                Usage.ff_record('geocode', 1, employee=employee)
            if names:
                return names, 'google'
        return self._ff_open_names(latitude, longitude), 'open'

    @api.model
    def _ff_google_names(self, latitude, longitude):
        """(names, billed): Google's locality and district names; billed once Google answered at all."""
        key = google_maps_key(self.env)
        if not key:
            return [], False
        try:
            payload = requests.get(GEOCODE_URL, timeout=TIMEOUT, params={
                'latlng': '%s,%s' % (latitude, longitude), 'key': key}).json()
        except (requests.RequestException, ValueError) as error:
            _logger.warning('Field Force: Google place lookup failed (%s)', error)
            return [], False
        status = payload.get('status')
        billed = status in ('OK', 'ZERO_RESULTS')
        if status != 'OK' or not payload.get('results'):
            return [], billed
        components = payload['results'][0].get('address_components', [])
        names = []
        for kind in ('locality', 'administrative_area_level_2', 'administrative_area_level_3', 'sublocality_level_1'):
            for component in components:
                if kind in component.get('types', []) and component['long_name'] not in names:
                    names.append(component['long_name'])
        return names, billed

    @api.model
    def _ff_open_names(self, latitude, longitude):
        """OpenStreetMap's free lookup, as its policy asks: one request, a real User-Agent."""
        base = self.env['ir.config_parameter'].sudo().get_param('web.base.url') or 'odoo'
        try:
            payload = requests.get(NOMINATIM_URL, timeout=TIMEOUT, params={
                'lat': latitude, 'lon': longitude, 'format': 'jsonv2', 'zoom': 12, 'addressdetails': 1,
            }, headers={'User-Agent': 'Field Force app (%s)' % base, 'Accept-Language': 'en'}).json()
        except (requests.RequestException, ValueError) as error:
            _logger.warning('Field Force: OpenStreetMap place lookup failed (%s)', error)
            return []
        address = payload.get('address') or {}
        names = []
        for key in ('city', 'town', 'village', 'municipality', 'county', 'state_district', 'suburb'):
            value = address.get(key)
            if value and value not in names:
                names.append(value)
        return names

    @api.model
    def _ff_match_district(self, names):
        """The City / District of the office's list that these place names point at."""
        District = self.env['ff.district'].sudo()
        districts = District.search([])
        lowered = [(d, (d.name or '').strip().lower()) for d in districts]
        for name in names:
            wanted = name.strip().lower()
            for district, text in lowered:
                if text and text == wanted:
                    return district
        for name in names:
            wanted = name.strip().lower()
            for district, text in lowered:
                if text and (text in wanted or wanted in text):
                    return district
        return District.browse()
