import logging
import re

import requests

from odoo import api, models

_logger = logging.getLogger(__name__)


class FfPincode(models.AbstractModel):
    """One function for new and old contacts: a PIN code gives the District / Territory, City / Town and Areas, which are
    found in the masters or made there (flagged ``api_created``)."""
    _name = 'ff.pincode.resolver'
    _description = 'PIN code to District / City / Area'

    @api.model
    def ff_lookup(self, pin):
        """The places of a PIN code: ``[{locality, taluk_block, district, state, pincode}]`` (empty when unknown)."""
        code = (pin or '').strip()
        if not re.fullmatch(r'[0-9]{6}', code):
            return []
        try:
            payload = requests.get('https://api.postalpincode.in/pincode/%s' % code, timeout=8).json()
        except (requests.RequestException, ValueError) as error:
            _logger.warning('Field Force: PIN lookup failed (%s)', error)
            return []
        offices = ((payload[0] if isinstance(payload, list) and payload else {}).get('PostOffice')) or []
        seen, rows = set(), []
        for o in offices:
            row = {'locality': (o.get('Name') or '').strip(), 'taluk_block': (o.get('Block') or '').strip(),
                   'district': (o.get('District') or '').strip(), 'state': (o.get('State') or '').strip(),
                   'pincode': code}
            key = (row['locality'].lower(), row['taluk_block'].lower())
            if row['locality'] and key not in seen:
                seen.add(key)
                rows.append(row)
        return rows

    @api.model
    def _ff_district(self, row, create):
        District, State = self.env['ff.district'].sudo(), self.env['res.country.state'].sudo()
        state = State.search([('country_id.code', '=', 'IN'), ('name', '=ilike', row['state'])], limit=1)
        if not state:
            return District.browse()
        district = District.search([('name', '=ilike', row['district']), ('state_id', '=', state.id)], limit=1)
        if district or not create:
            return district
        # A new District / Territory needs a Region: the one the other districts of that state already use.
        regions = District.search([('state_id', '=', state.id), ('team_id', '!=', False)]).mapped('team_id')
        if len(regions) != 1:
            _logger.info('Field Force: %s (%s) not created: the Region of that state is not one', row['district'], row['state'])
            return District.browse()
        return District.create({'name': row['district'].upper(), 'code': row['district'].upper(), 'state_id': state.id,
                                'team_id': regions.id, 'api_created': True})

    @api.model
    def ff_resolve(self, pin, create=True):
        """Find (or, with ``create``, make) the masters of a PIN code. Returns ``{'found', 'district', 'cities', 'areas'}``
        where ``cities`` and ``areas`` are record sets; ``areas`` are all the localities of the PIN code."""
        rows = self.ff_lookup(pin)
        out = {'found': bool(rows), 'district': self.env['ff.district'], 'cities': self.env['ff.territory'],
               'areas': self.env['ff.area']}
        if not rows:
            return out
        Territory, Area = self.env['ff.territory'].sudo(), self.env['ff.area'].sudo()
        district = self._ff_district(rows[0], create)
        out['district'] = district
        if not district:
            return out
        for row in rows:
            town_name = row['taluk_block'] or row['district']
            city = Territory.search([('name', '=ilike', town_name), ('district_id', '=', district.id)], limit=1)
            if not city and create:
                city = Territory.create({'name': town_name.upper(), 'code': town_name.upper(), 'district_id': district.id,
                                         'api_created': True})
            if not city:
                continue
            out['cities'] |= city
            area = Area.search([('name', '=ilike', row['locality']), ('territory_id', '=', city.id)], limit=1)
            if not area and create:
                area = Area.create({'name': row['locality'].upper(), 'territory_id': city.id, 'api_created': True})
            out['areas'] |= area
        return out
