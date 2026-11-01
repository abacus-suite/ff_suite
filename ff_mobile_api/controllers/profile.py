"""The employee's own photo, shown on their profile and the Home screen."""
import base64
import hashlib

from odoo import fields as odoo_fields
from odoo import http
from odoo.http import request

from .clients import to_int
from .common import ApiError, api_route, body, ok

MAX_BYTES = 3 * 1024 * 1024


def photo_version(employee):
    """Changes whenever the photo does, so the app knows to fetch it again."""
    raw = employee.sudo().image_128
    return hashlib.sha1(raw).hexdigest()[:12] if raw else None


class FieldForceProfileApi(http.Controller):

    @api_route('/api/v1/me/photo', methods=('GET',))
    def my_photo(self, employee, size=None, **kw):
        return self._photo(employee, size)

    @api_route('/api/v1/employees/<int:employee_id>/photo', methods=('GET',))
    def employee_photo(self, employee, employee_id, size=None, **kw):
        target = request.env['hr.employee'].sudo().browse(employee_id).exists()
        if not target or (target != employee and target not in employee._ff_subordinates()
                          and target != employee.parent_id):
            raise ApiError('Employee not found.', 404, 'not_found')
        return self._photo(target, size)

    def _photo(self, employee, size):
        field = {'128': 'image_128', '512': 'image_512'}.get(str(to_int(size) or ''), 'image_512')
        data = employee.sudo()[field]
        if not data:
            raise ApiError('No photo yet.', 404, 'not_found')
        raw = base64.b64decode(data)  # image fields are read as base64
        mime = 'image/png' if raw[:4] == b'\x89PNG' else 'image/jpeg'
        return request.make_response(raw, headers=[('Content-Type', mime), ('Cache-Control', 'private, max-age=86400')])

    # The name card changes colour with the designation (start, end).
    DESIGNATION_COLOURS = [
        (('stock & despatch coordinator [nesto]', 'stock & despatch coordinator', 'sales representative & merchandiser',
          'sales representative', 'sales officer', 'brand promoter', 'brand activation & collaboration executive'),
         ('#38D9C0', '#0B5FA5')),
        (('senior sales officer', 'sales team lead'), ('#7ED957', '#00796B')),
        (('sales operations manager', 'asst manager - sales & marketing', 'asst manager – sales & marketing',
          'assistant manager - sales & marketing', 'assistant manager – sales & marketing'),
         ('#F44336', '#7F0000')),
        (('manager - central kerala', 'manager – central kerala'), ('#B794F4', '#44208F')),
        (('growth officer', 'growth manager - bangalore', 'growth manager – bangalore', 'growth manager'),
         ('#FFC000', '#E65100')),
        (('hr officer',), ('#FF8AF0', '#A0148C')),
    ]

    @classmethod
    def designation_gradient(cls, designation):
        if not designation:
            return ('#38D9C0', '#0B5FA5')
        import re
        raw = designation.lower().strip()
        norm = re.sub(r'\[.*?\]|\(.*?\)', '', raw)
        norm = norm.replace('–', '-').replace('—', '-').strip()
        norm = ' '.join(norm.split())

        for names, colours in cls.DESIGNATION_COLOURS:
            for n in names:
                n_clean = n.lower().replace('–', '-').strip()
                if raw == n or norm == n_clean:
                    return colours

        if any(w in norm for w in ('hr officer', 'human resources', 'hr')):
            return ('#FF8AF0', '#A0148C')
        if any(w in norm for w in ('growth manager', 'growth officer', 'growth')):
            return ('#FFC000', '#E65100')
        if 'central kerala' in norm:
            return ('#B794F4', '#44208F')
        if any(w in norm for w in ('sales operations', 'asst manager', 'assistant manager', 'operations manager',
                                   'sales & marketing', 'sales and marketing')):
            return ('#F44336', '#7F0000')
        if any(w in norm for w in ('senior sales officer', 'sales team lead', 'team lead')):
            return ('#7ED957', '#00796B')
        if any(w in norm for w in ('coordinator', 'merchandiser', 'sales representative', 'sales officer',
                                   'promoter', 'activation', 'stock', 'despatch', 'dispatch')):
            return ('#38D9C0', '#0B5FA5')

        return ('#38D9C0', '#0B5FA5')

    @api_route('/api/v1/me/profile-details', methods=('GET',))
    def profile_details(self, employee, **kw):
        """What the My Profile page lists: teams, territories, beats, details and the company."""
        e = employee.sudo()
        company = e.company_id or request.env.company
        designation = (e.ff_designation_id.name or (e.job_id.name if hasattr(e, 'job_id') and e.job_id else '') or e.job_title or '').strip()
        colours = self.designation_gradient(designation)

        # Teams
        teams = e.ff_team_id
        if 'ff.team' in request.env:
            teams |= request.env['ff.team'].sudo().search([
                '|', ('manager_id', '=', e.id), ('member_ids', 'in', [e.id])
            ])
        teams = teams.filtered(lambda t: t.exists())

        # Territories
        Territory = request.env.get('ff.territory', request.env['res.partner'])
        territories = e.ff_territory_ids.filtered(lambda t: t.exists()) if 'ff_territory_ids' in e._fields else Territory.browse()
        secondary = e.ff_secondary_territory.filtered(lambda t: t.exists()) if 'ff_secondary_territory' in e._fields else Territory.browse()
        secondary = secondary - territories
        outside = []
        if 'ff.contact.access.request' in request.env:
            today = odoo_fields.Date.context_today(e)
            grants = request.env['ff.contact.access.request'].sudo().search([
                ('employee_id', '=', e.id), ('scope_type', '=', 'territory'), ('state', '=', 'approved'),
                ('date_from', '<=', today), ('date_to', '>=', today)])
            outside = [t for t in grants.mapped('territory_id').filtered(lambda t: t.exists()) if t not in territories and t not in secondary]

        # Beats
        Beat = request.env.get('ff.beat', request.env['res.partner']).sudo()
        beats = e.ff_route_ids.filtered(lambda b: b.exists()) if 'ff_route_ids' in e._fields else Beat.browse()
        if hasattr(e, '_ff_territory_beats'):
            try:
                beats |= e._ff_territory_beats().filtered(lambda b: b.exists())
            except Exception:
                pass
        if hasattr(Beat, 'ff_beats_for'):
            try:
                beats |= Beat.ff_beats_for(e).filtered(lambda b: b.exists())
            except Exception:
                pass

        # A one-time beat is for its date only: it is not listed with the person's beats.
        beats = beats.filtered(lambda b: getattr(b, 'ff_schedule', False) != 'one_time' or getattr(b, 'ff_approval_state', 'approved') != 'approved')

        # If territories was empty, check if beats have mapped territory
        if not territories and 'territory_id' in beats._fields:
            territories = beats.mapped('territory_id').filtered(lambda t: t.exists())

        # If teams was empty, check if beats have mapped team
        if not teams and hasattr(beats, 'team_id'):
            teams |= beats.mapped('team_id').filtered(lambda t: t.exists())

        # The company as the office holds it: the full GSTIN and the full links, so the app can show and open them.
        gstin = (company.vat or '').strip().upper().replace(' ', '')
        website = (company.website or '').strip()
        instagram = ((getattr(company, 'ff_instagram', None) or getattr(company, 'social_instagram', None)) or '').strip()
        # Working hours: the length of the shift, else the hours of the working schedule.
        working_hours = None
        shift = e.ff_shift_id if 'ff_shift_id' in e._fields else False
        if shift and shift.end_time != shift.start_time:
            span = shift.end_time - shift.start_time
            working_hours = round(span if span > 0 else span + 24, 2)
        elif 'resource_calendar_id' in e._fields and e.resource_calendar_id.hours_per_day:
            working_hours = round(e.resource_calendar_id.hours_per_day, 2)

        return ok({
            'status': 'Active' if e.active else 'Inactive',
            'designation': designation or None,
            'colour': {'start': colours[0], 'end': colours[1]},
            'teams': [{'id': t.id, 'name': t.name, 'lead': t.manager_id.name or None,
                       'members': len(t.member_ids)} for t in teams],
            'territories': {
                'primary': [{'id': t.id, 'name': t.name, 'region': (t.district_id.name if 'district_id' in t._fields and t.district_id else None)} for t in territories],
                'secondary': [{'id': t.id, 'name': t.name, 'region': (t.district_id.name if 'district_id' in t._fields and t.district_id else None)}
                              for t in secondary],
                'outside': [{'id': t.id, 'name': t.name, 'region': (t.district_id.name if 'district_id' in t._fields and t.district_id else None)} for t in outside],
            },
            'beats': [{
                'id': b.id, 'name': b.name,
                'outlets': getattr(b, 'client_count', 0) or len(b.line_ids),
                'city': (b.district_id.name if 'district_id' in b._fields and b.district_id else None) or (b.territory_id.district_id.name if 'territory_id' in b._fields and b.territory_id and b.territory_id.district_id else None),
                'state': 'pending' if getattr(b, 'ff_approval_state', 'approved') == 'pending' else 'approved',
            } for b in beats.sorted(lambda r: (r.name or '').lower())],
            'details': {
                'reports_to': e.parent_id.name or None,
                'department': e.department_id.name or None,
                'employee_id': e.ff_employee_code or None,
                'working_hours': working_hours,
            },
            'company': {
                'name': company.name or None,
                'gstin': gstin or None,
                'website': website or None,
                'instagram': instagram or None,
            },
        })

    @api_route('/api/v1/me/photo', methods=('POST',))
    def set_photo(self, employee, **kw):
        image = body().get('image') or ''
        if ',' in image[:80]:
            image = image.split(',', 1)[1]
        try:
            raw = base64.b64decode(image, validate=True)
        except ValueError:
            raise ApiError('The photo could not be read.')
        if not raw or len(raw) > MAX_BYTES:
            raise ApiError('Choose a photo under 3 MB.')
        employee.sudo().write({'image_1920': base64.b64encode(raw)})
        employee.sudo().message_post(body='Profile photo changed from the app.')
        return ok({'photo_version': photo_version(employee)})
