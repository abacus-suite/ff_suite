import json
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
    def _ff_district(self, row, create, region=None, why=None):
        District, State = self.env['ff.district'].sudo(), self.env['res.country.state'].sudo()
        state = State.search([('country_id.code', '=', 'IN'), ('name', '=ilike', row['state'])], limit=1)
        if not state:
            # Spelling differences (Tamilnadu / Tamil Nadu, & / and): compare without spaces and punctuation.
            def norm(text):
                return re.sub(r'[^a-z]', '', (text or '').lower().replace('&', 'and'))
            state = next((s for s in State.search([('country_id.code', '=', 'IN')]) if norm(s.name) == norm(row['state'])),
                         State.browse())
        if not state:
            why.append('state "%s" is not in Odoo States' % row['state'])
            return District.browse()
        district = District.search([('name', '=ilike', row['district']), ('state_id', '=', state.id)], limit=1)
        if district or not create:
            return district
        # A new District / Territory needs a Region. First the office's map (System Parameter
        # ``ff_base.pincode_region_map``, JSON such as {"ernakulam": "CENTRAL KERALA", "kerala": "SOUTH KERALA"}: a
        # district name wins over a state name); else the one Region the other districts of that state already use.
        # The contact's own Region comes first when it has one.
        team = region[:1] if region else self.env['ff.team'].browse()
        try:
            region_map = {str(k).strip().lower(): v for k, v in json.loads(
                self.env['ir.config_parameter'].sudo().get_param('ff_base.pincode_region_map') or '{}').items()}
        except ValueError:
            region_map = {}
        wanted = region_map.get(row['district'].strip().lower()) or region_map.get(row['state'].strip().lower())
        if wanted and not team:
            team = self.env['ff.team'].sudo().search([('name', '=ilike', str(wanted))], limit=1)
        if not team:
            regions = District.search([('state_id', '=', state.id), ('team_id', '!=', False)]).mapped('team_id')
            team = regions if len(regions) == 1 else self.env['ff.team'].browse()
        if not team:
            why.append('no Region for district "%s"' % row['district'])
            _logger.info('Field Force: %s (%s) not created: no Region is set for it (ff_base.pincode_region_map)',
                         row['district'], row['state'])
            return District.browse()
        return District.create({'name': row['district'].upper(), 'code': row['district'].upper(), 'state_id': state.id,
                                'team_id': team.id, 'api_created': True})

    @api.model
    def ff_resolve(self, pin, create=True, region=None):
        """Find (or, with ``create``, make) the masters of a PIN code. Returns ``{'found', 'district', 'cities', 'areas'}``
        where ``cities`` and ``areas`` are record sets; ``areas`` are all the localities of the PIN code."""
        why = []
        rows = self.ff_lookup(pin)
        out = {'why': '', 'found': bool(rows), 'district': self.env['ff.district'], 'cities': self.env['ff.territory'],
               'areas': self.env['ff.area']}
        if not rows:
            out['why'] = 'no PIN code answer (not a 6-digit PIN, or the PIN service did not reply)'
            return out
        Territory, Area = self.env['ff.territory'].sudo(), self.env['ff.area'].sudo()
        district = self._ff_district(rows[0], create, region, why)
        out['district'] = district
        if not district:
            out['why'] = why[0] if why else 'district not found'
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
