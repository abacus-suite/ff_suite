import math

from odoo import http
from odoo.exceptions import ValidationError
from odoo.http import request

from odoo.addons.ff_base.tools import haversine_m, to_iso

from .common import ApiError, api_route, body, ok, ref
from .field_data import client_data, visit_data

# A map of more points than this is a solid colour anyway, and the phone
# has to draw every one of them.
MAX_MAP_POINTS = 20000
MAX_LIMIT = 200
DEFAULT_RADIUS_KM = 25.0


def to_float(value):
    try:
        return float(value)
    except (TypeError, ValueError):
        return None


def to_int(value):
    try:
        return int(value)
    except (TypeError, ValueError):
        return None


def _route_partner_ids(people):
    """Customers standing on these people's routes or planned for their days."""
    env = request.env
    ids = set()
    if 'ff.beat.line' in env:
        routes = people.sudo().ff_route_ids
        if routes:
            ids.update(env['ff.beat.line'].sudo().search([('beat_id', 'in', routes.ids)]).partner_id.ids)
    if 'ff.route.plan.customer' in env:
        ids.update(env['ff.route.plan.customer'].sudo().search(
            [('day_id.employee_id', 'in', people.ids)]).partner_id.ids)
    # What a manager gave them (or they were granted) for a beat, territory or city.
    partner = env['res.partner']
    if hasattr(partner, '_ff_grant_partner_ids'):
        ids.update(partner._ff_grant_partner_ids(people))
    return list(ids)


def _own_ids(employee, extra_ids):
    """The contacts that are this person's own: given to them by name, in their primary or secondary territories, or on
    their routes and plans."""
    employee = employee.sudo()
    Partner = request.env['res.partner'].sudo()
    terms = [('ff_employee_ids', 'in', employee.ids)]
    territories = employee.ff_territory_ids if 'ff_territory_ids' in employee._fields else request.env['ff.territory']
    for name in ('ff_secondary_territory', 'ff_secondary_territory_ids'):
        if name in employee._fields and employee[name]:
            territories |= employee[name]
    if territories and 'ff_territory_id' in Partner._fields:
        terms.append(('ff_territory_id', 'in', territories.ids))
        if 'ff_secondary_territory_ids' in Partner._fields:
            terms.append(('ff_secondary_territory_ids', 'in', territories.ids))
    ids = set(Partner.search([('ff_is_client', '=', True)] + ['|'] * (len(terms) - 1) + terms).ids)
    ids.update(extra_ids or [])
    return list(ids)


def _mark(name):
    """Remember which rule built the list, for the diagnostic screen."""
    request.httprequest.environ['ff_clients_rule'] = name


def _territory_only_domain(employee):
    """Employee mode (a manager too) with "Contacts shown by: Territory wise" and no contact rule of their own: the
    contacts of the person's primary and secondary territories, and nothing else. None when it does not apply (another
    kind of visibility, a rule on the person, or no territory set), so the usual rules decide."""
    Partner = request.env['res.partner'].sudo()
    mode = request.env['ir.config_parameter'].sudo().get_param('ff_base.contact_visibility') or 'territory'
    if mode != 'territory' or Partner._ff_access_rule(employee):
        return None
    emp = employee.sudo()
    territories = emp.ff_territory_ids if 'ff_territory_ids' in emp._fields else request.env['ff.territory']
    if 'ff_secondary_territory' in emp._fields:
        territories |= emp.ff_secondary_territory
    if not territories or 'ff_territory_id' not in Partner._fields:
        return None
    # Exactly this: the contact's Territory, or its Secondary Territories, is one of the person's. A beat the
    # contact happens to be on does not count: a beat can carry contacts from anywhere.
    places = [('ff_territory_id', 'in', territories.ids)]
    if 'ff_secondary_territory_ids' in Partner._fields:
        places = ['|'] + places + [('ff_secondary_territory_ids', 'in', territories.ids)]
    return [('ff_is_client', '=', True),
            ('company_id', 'in', (False, emp.company_id.id)),
            '|', '|', ('ff_approval_state', '=', 'approved'), ('ff_approval_state', '=', False),
            '&', ('ff_approval_state', '=', 'pending'), ('ff_created_by_employee_id', '=', emp.id)] + places


def _with_routes(domain, extra_ids):
    """The domain, widened by the customers of the routes and the plans.

    The two sets are joined by their ids rather than by an "or" of two
    domains: the first one already carries its own operators, and rewriting
    those by hand is how mistakes creep in.
    """
    if not extra_ids:
        return domain
    Partner = request.env['res.partner'].sudo()
    ids = set(Partner.search(domain).ids)
    ids.update(Partner.search([('ff_is_client', '=', True), ('id', 'in', extra_ids)]).ids)
    return [('id', 'in', list(ids))]


def client_domain(employee, member=None):
    """The contacts the app may show: ``_client_domain`` less any category hidden from the app."""
    base = _client_domain(employee, member)
    shown = ['|', ('ff_category_id', '=', False), ('ff_category_id.show_in_app', '=', True)]
    # "Allocated Outlets / Distributors" on the employee: only those with their name on them.
    Partner = request.env['res.partner']
    allocation = Partner._ff_allocation_domain(employee) if hasattr(Partner, '_ff_allocation_domain') else []
    try:
        from odoo.fields import Domain
        return list(Domain(base) & Domain(shown) & Domain(allocation))
    except Exception:
        return base + shown + allocation


def _client_domain(employee, member=None):
    """Contacts the app may show.

    A manager sees their own and, through ``member``, one person of their team
    or the whole team at once. Every category any of them may use is allowed,
    so a team spread over departments still shows all its kinds of contact.
    """
    # A manager's list is their team's list: their own contacts and everybody's
    # under them, unless they ask for one person or for themselves alone.
    people = employee | employee._ff_subordinates()
    if member in (None, ''):
        member = 'team'
    if member == 'me':
        people = employee
    elif member != 'team':
        team = employee._ff_subordinates()
        try:
            chosen = team.filtered(lambda e, m=int(member): e.id == m)
        except (TypeError, ValueError):
            chosen = team.browse()
        if not chosen:
            raise ApiError('That person is not in your team.', 403, 'forbidden')
        people = chosen
    # Customers on the routes these people work, or planned for one of their
    # days, belong in the list even when nobody assigned them by name.
    extra = _route_partner_ids(people)
    # In employee mode (a manager too) the list is the person's own territories, primary and secondary, not their
    # team's: territory-wise, unless a contact rule or the employee's allocation switches say otherwise.
    Partner = request.env['res.partner'].with_context(ff_only_me=True) if member == 'me' else request.env['res.partner']
    if member == 'me':
        own = _territory_only_domain(employee)
        if own is not None:
            _mark('territory_only')
            # Territory-wise means the territories: his beats' and planned days' contacts from elsewhere do not
            # come in; only what was granted to him on purpose (contact access) does.
            granted = Partner._ff_grant_partner_ids(people) if hasattr(Partner, '_ff_grant_partner_ids') else []
            return _with_routes(own, list(granted))
    if member == 'team' and Partner._ff_see_all():
        _mark('team_see_all')
        return Partner._ff_visible_domain(employee)
    if Partner._ff_access_rule(employee) or Partner._ff_contact_access() == 'open':
        # The office shares the contacts: everybody's list is the company's list,
        # narrowed only when somebody is picked out of the team.
        _mark('rule_or_open_access')
        domain = Partner._ff_visible_domain(employee)
        if member == 'me':
            # "Only me": my own contacts, not the whole company's list.
            domain = domain + [('id', 'in', _own_ids(employee, extra))]
        elif member != 'team':
            domain = domain + [('ff_employee_ids', 'in', people.ids)]
        return domain
    if employee.ff_access_scope == 'all':
        _mark('scope_all')
        domain = [('ff_is_client', '=', True), ('ff_approval_state', '!=', 'rejected')]
        # Somebody who sees everything only narrows down when they pick themselves or one person.
        if member == 'me':
            domain.append(('id', 'in', _own_ids(employee, extra)))
        elif member != 'team':
            domain.append(('ff_employee_ids', 'in', people.ids))
        return domain
    if people == employee:
        _mark('own_visible_domain')
        return _with_routes(Partner._ff_visible_domain(employee), extra)
    Category = request.env['ff.contact.category']
    categories = Category.browse()
    for person in people:
        categories |= Category.ff_for_employee(person)
    return _with_routes([
        ('ff_is_client', '=', True),
        ('ff_category_id', 'in', categories.ids),
        ('ff_employee_ids', 'in', people.ids),
        ('ff_approval_state', '!=', 'rejected'),
    ], extra)


def visible_client(employee, partner_id):
    Partner = request.env['res.partner'].sudo()
    partner = Partner.search(client_domain(employee) + [('id', '=', partner_id)], limit=1)
    if not partner:
        # A customer on one of my routes, or planned for me or my team, is always mine to open
        # even when its category or assignment would otherwise hide it.
        people = employee | employee._ff_subordinates()
        on_route = request.env['ff.beat.line'].sudo().search_count([
            ('partner_id', '=', partner_id), ('beat_id', 'in', employee.sudo().ff_route_ids.ids)])
        planned = request.env['ff.route.plan.customer'].sudo().search_count([
            ('partner_id', '=', partner_id), ('day_id.employee_id', 'in', people.ids)])
        if on_route or planned:
            partner = Partner.browse(partner_id).exists()
    if not partner:
        # A distributor in the company is always accessible to visit, take demand or collect samples
        dist_domain = [
            ('id', '=', partner_id),
            ('active', '=', True),
            ('company_id', 'in', (False, employee.company_id.id)),
            '|', ('ff_category_type', '=', 'distributor'),
            '&', ('ff_is_distributor', '=', True),
                 ('ff_category_type', 'not in', ('outlet', 'customer', 'lead', 'other')),
        ]
        partner = Partner.search(dist_domain, limit=1)
    if not partner:
        raise ApiError('Client not found.', 404, 'not_found')
    return partner


def category_for(employee, category_id):
    """Contact category chosen in the app, restricted to the employee's department."""
    allowed = request.env['ff.contact.category'].ff_for_employee(employee)
    if category_id:
        category = allowed.filtered(lambda c: c.id == to_int(category_id))
        if not category:
            raise ApiError('You do not have access to this contact category.', 403, 'forbidden')
        return category
    if len(allowed) == 1:
        return allowed
    raise ApiError('category_id is required: choose a contact category.')


def _outlet_filter(Partner):
    """Filters res.partner to genuine retail outlets only, excluding distributors and leads."""
    conds = [
        '|', ('ff_category_type', '=', False),
             ('ff_category_type', 'not in', ('distributor', 'lead')),
        ('ff_is_distributor', '!=', True),
    ]
    if 'is_distributor' in Partner._fields:
        conds.append(('is_distributor', '!=', True))
    return conds


def _distributor_filter(Partner):
    conds = ['|', ('ff_category_type', '=', 'distributor'), ('ff_is_distributor', '=', True)]
    if 'is_distributor' in Partner._fields:
        conds = ['|'] + conds + [('is_distributor', '=', True)]
    return conds


def _location_domain(Partner, territory_id=None, beat_id=None, kw=None):
    """The territory, area, city and beat filters of the client list, as a domain.

    The count boxes use the very same domain, so they always agree with the list.
    """
    kw = kw or {}
    domain = []
    if territory_id:
        tid = to_int(territory_id)
        if 'ff_secondary_territory_ids' in Partner._fields:
            domain += ['|', '|', ('ff_territory_id', '=', tid),
                                 ('ff_secondary_territory_ids', 'in', [tid]),
                                 ('ff_beat_line_ids.beat_id.territory_id', '=', tid)]
        elif 'ff_territory_id' in Partner._fields:
            domain += ['|', ('ff_territory_id', '=', tid), ('ff_beat_line_ids.beat_id.territory_id', '=', tid)]
        else:
            domain += [('ff_beat_line_ids.beat_id.territory_id', '=', tid)]
    if kw.get('area_id') and 'ff_area_id' in Partner._fields:
        domain.append(('ff_area_id', '=', to_int(kw['area_id'])))
    district_id = kw.get('district_id') or kw.get('city_id')
    if district_id:
        did = to_int(district_id)
        if 'ff_secondary_district_ids' in Partner._fields:
            domain += ['|', '|', ('ff_district_id', '=', did),
                                 ('ff_secondary_district_ids', 'in', [did]),
                                 ('ff_beat_line_ids.beat_id.district_id', '=', did)]
        else:
            domain += ['|', ('ff_district_id', '=', did), ('ff_beat_line_ids.beat_id.district_id', '=', did)]
    if beat_id:
        domain.append(('ff_beat_line_ids.beat_id', '=', to_int(beat_id)))
    beat_ids = [to_int(x) for x in str(kw.get('beat_ids') or '').split(',') if to_int(x)]
    if beat_ids:
        domain.append(('ff_beat_line_ids.beat_id', 'in', beat_ids))
    return domain


def _category_counts(employee, member=None, category_type=None, extra=None):
    """How many contacts of each kind the person may see, for the chips."""
    Partner = request.env['res.partner'].sudo()
    base = client_domain(employee, member) + (extra or [])
    if category_type == 'distributor':
        count_base = base + _distributor_filter(Partner)
    elif category_type == 'lead':
        count_base = base + [('ff_category_type', '=', 'lead')]
    elif category_type == 'outlet':
        count_base = base + _outlet_filter(Partner)
    else:  # All / None -> all categories
        count_base = base
    total = Partner.search_count(count_base)
    never = Partner.search_count(count_base + [('ff_last_visit_at', '=', False)])
    grand_total = Partner.search_count(base) if count_base != base else total

    groups = Partner._read_group(base, ['ff_category_id'], ['__count'])
    def _mapped_type(category):
        ctype = category.category_type or ''
        cname = (category.name or '').lower()
        if ctype == 'distributor' or 'distributor' in cname:
            return 'distributor'
        if ctype == 'lead' or 'lead' in cname:
            return 'lead'
        return 'outlet'

    by_category = [{
        'id': category.id,
        'name': category.name,
        'type': _mapped_type(category),
        'count': count,
    } for category, count in groups if category]
    by_category.sort(key=lambda row: -row['count'])
    return {'total': total, 'grand_total': grand_total, 'categories': by_category, 'never_visited': never}


class FieldForceClientsApi(http.Controller):

    @api_route('/api/v1/clients/map', methods=('GET',))
    def clients_map(self, employee, q=None, category_id=None, member=None, **kw):
        """Every located contact, as points, for the map."""
        Partner = request.env['res.partner'].sudo()
        domain = client_domain(employee, member) + [('partner_latitude', '!=', False)]
        if kw.get('exclude_leads') in ('1', 'true', 'True', 1, True):
            domain.append(('ff_category_type', '!=', 'lead'))
        category_type = kw.get('category_type')
        if category_type == 'outlet':
            domain += _outlet_filter(Partner)
            if category_id:
                domain.append(('ff_category_id', '=', to_int(category_id)))
        elif category_type == 'distributor':
            domain += _distributor_filter(Partner)
            if category_id:
                domain.append(('ff_category_id', '=', to_int(category_id)))
        elif category_id:
            cid = to_int(category_id)
            domain.append(('ff_category_id', '=', cid))
        elif category_type:
            domain.append(('ff_category_type', '=', category_type))

        if q:
            domain += ['|', '|', '|', ('name', 'ilike', q), ('ff_client_code', 'ilike', q),
                       ('phone', 'ilike', q), ('city', 'ilike', q)]
        rows = Partner.search_read(
            domain, ['id', 'name', 'partner_latitude', 'partner_longitude',
                     'ff_approval_state', 'ff_category_type'],
            limit=MAX_MAP_POINTS)
        return ok({
            'total': len(rows),
            'points': [{
                'id': row['id'],
                'name': row['name'],
                'lat': row['partner_latitude'],
                'lng': row['partner_longitude'],
                'approval_state': row['ff_approval_state'],
                'category_type': row['ff_category_type'],
            } for row in rows if row['partner_latitude'] or row['partner_longitude']],
        })

    @api_route('/api/v1/clients/rule-debug', methods=('GET',))
    def clients_rule_debug(self, employee, member=None, **kw):
        """Which rule built this person's client list, and the settings behind it (for the app's diagnostic)."""
        Partner = request.env['res.partner'].sudo()
        params = request.env['ir.config_parameter'].sudo()
        domain = client_domain(employee, member or 'me')
        emp = employee.sudo()
        rule = Partner._ff_access_rule(employee)
        return ok({
            'build': 'territory-only-1cd334c',
            'rule_used': request.httprequest.environ.get('ff_clients_rule'),
            'member': member or 'me',
            'contact_visibility': params.get_param('ff_base.contact_visibility') or '(unset: territory)',
            'contact_access': params.get_param('ff_base.contact_access') or '(unset: scoped)',
            'contact_see_all': params.get_param('ff_base.contact_see_all') or '(unset: true)',
            'contact_rule': rule.display_name if rule else None,
            'access_scope': emp.ff_access_scope,
            'territories': emp.ff_territory_ids.mapped('name'),
            'secondary_territories': emp.ff_secondary_territory.mapped('name') if 'ff_secondary_territory' in emp._fields else [],
            'allocated_outlets': bool(emp.ff_allocated_outlets),
            'allocated_distributors': bool(emp.ff_allocated_distributors),
            'count': Partner.search_count(domain),
            'by_territory': {(t.name or '?'): n for t, n in Partner._read_group(domain, ['ff_territory_id'], ['__count'])},
        })

    @api_route('/api/v1/clients/filters', methods=('GET',))
    def client_filters(self, employee, **kw):
        e = employee.sudo()
        Territory = request.env['ff.territory'] if 'ff.territory' in request.env else None
        Beat = request.env['ff.beat'] if 'ff.beat' in request.env else None
        primary = e.ff_territory_ids if 'ff_territory_ids' in e._fields else (Territory.browse() if Territory else request.env['res.partner'].browse())
        secondary = e.ff_secondary_territory if 'ff_secondary_territory' in e._fields \
            else (Territory.browse() if Territory else request.env['res.partner'].browse())
        beats = e.ff_route_ids if 'ff_route_ids' in e._fields else (Beat.browse() if Beat else request.env['res.partner'].browse())
        team = e._ff_subordinates()
        mine = (primary | secondary) if Territory else primary
        others = Territory.browse() if Territory else primary.browse()
        if 'ff_territory_ids' in e._fields:
            others = (team.mapped('ff_territory_ids') | team.mapped('ff_secondary_territory') |
                      beats.mapped('territory_id')) - mine
        beats = beats | (mine | others).mapped('beat_ids') if (mine or others) else beats
        # The Area master of each territory, so the filter lists the real areas (empty ones too).
        areas = {}
        if 'ff.area' in request.env:
            for area in request.env['ff.area'].sudo().search([('territory_id', 'in', (mine | others).ids)]):
                areas.setdefault(area.territory_id.id, []).append({'id': area.id, 'name': area.name})

        def territory_row(t, kind):
            return {'id': t.id, 'name': t.name, 'kind': kind, 'areas': areas.get(t.id, [])}

        return ok({
            'territories': [territory_row(t, 'primary') for t in primary.sorted(lambda r: (r.name or '').lower())] +
                           [territory_row(t, 'secondary') for t in secondary.sorted(lambda r: (r.name or '').lower()) if t not in primary] +
                           [territory_row(t, 'other') for t in others.sorted(lambda r: (r.name or '').lower())],
            'beats': [{'id': b.id, 'name': b.name,
                       'territory_id': b.territory_id.id if 'territory_id' in b._fields and b.territory_id else None}
                      for b in beats.sorted(lambda r: (r.name or '').lower())],
        })

    @api_route('/api/v1/clients', methods=('GET',))
    def clients(self, employee, q=None, category_id=None, lat=None, lng=None, radius_km=None,
                limit=None, offset=None, member=None, never_visited=None, territory_id=None, beat_id=None,
                **kw):
        Partner = request.env['res.partner'].sudo()
        domain = client_domain(employee, member)
        location = _location_domain(Partner, territory_id, beat_id, kw)
        if kw.get('exclude_leads') in ('1', 'true', 'True', 1, True):
            # Outlets and distributors only: for a PO or a payment, which are never for a lead.
            location = location + [('ff_category_type', '!=', 'lead')]
        domain += location
        if never_visited in ('1', 'true', 'True', 1, True):
            domain.append(('ff_last_visit_at', '=', False))
        if q:
            domain += ['|', '|', '|', ('name', 'ilike', q), ('ff_client_code', 'ilike', q),
                       ('phone', 'ilike', q), ('city', 'ilike', q)]
        category_type = kw.get('category_type')
        if category_type == 'outlet':
            domain += _outlet_filter(Partner)
            if category_id:
                domain.append(('ff_category_id', '=', to_int(category_id)))
        elif category_type == 'distributor':
            domain += _distributor_filter(Partner)
            if category_id:
                domain.append(('ff_category_id', '=', to_int(category_id)))
        elif category_id:
            cid = to_int(category_id)
            domain.append(('ff_category_id', '=', cid))
        elif category_type:
            domain.append(('ff_category_type', '=', category_type))
        try:
            limit = min(int(limit or 50), MAX_LIMIT)
            offset = max(int(offset or 0), 0)
        except ValueError:
            raise ApiError('limit and offset must be numbers.')
        lat, lng = to_float(lat), to_float(lng)

        if lat is not None and lng is not None and kw.get('by_distance') in ('1', 'true', 'True', 1, True):
            # Everybody, nearest first, with no radius: the ones too far or without a position come after.
            def metres(p):
                if not (p.partner_latitude or p.partner_longitude):
                    return None
                return haversine_m(lat, lng, p.partner_latitude, p.partner_longitude)

            ranked = sorted(((metres(p), p) for p in Partner.search(domain)),
                            key=lambda row: (row[0] is None, row[0] or 0, (row[1].name or '').lower()))
            page = [p for _, p in ranked[offset:offset + limit]]
            return ok({'total': len(ranked),
                       'counts': _category_counts(employee, member, category_type=category_type, extra=location),
                       'clients': [client_data(p, lat, lng) for p in page]})

        if lat is not None and lng is not None:
            radius = to_float(radius_km) or DEFAULT_RADIUS_KM
            dlat = radius / 111.0
            dlng = dlat / max(math.cos(math.radians(lat)), 0.2)
            domain += [('partner_latitude', '>=', lat - dlat), ('partner_latitude', '<=', lat + dlat),
                       ('partner_longitude', '>=', lng - dlng), ('partner_longitude', '<=', lng + dlng)]
            rows = [client_data(p, lat, lng) for p in Partner.search(domain)]
            rows = sorted((r for r in rows if r['distance_m'] <= radius * 1000), key=lambda r: r['distance_m'])
            return ok({'total': len(rows), 'counts': _category_counts(employee, member, category_type=category_type, extra=location),
                       'clients': rows[offset:offset + limit]})

        total = Partner.search_count(domain)
        partners = Partner.search(domain, order='name', limit=limit, offset=offset)
        return ok({'total': total, 'counts': _category_counts(employee, member, category_type=category_type, extra=location),
                   'clients': [client_data(p) for p in partners]})

    @api_route('/api/v1/clients/<int:partner_id>', methods=('GET',))
    def client(self, employee, partner_id, lat=None, lng=None, **kw):
        partner = visible_client(employee, partner_id)
        visits = request.env['ff.visit'].sudo().search([('partner_id', '=', partner.id)], limit=5)
        sites = partner.child_ids.filtered(lambda c: c.ff_is_client and c.ff_approval_state == 'approved')
        data = client_data(partner, to_float(lat), to_float(lng))
        if hasattr(partner, 'ff_onboarding_payload') and partner.sudo().ff_category_type in ('outlet', 'distributor', 'lead'):
            data['onboarding'] = partner.ff_onboarding_payload()
        # Checking in on arrival only happens where the person meant to go today,
        # so the app is told whether this customer is on the day's plan.
        planned = request.env['ff.route.plan.customer'].sudo().search_count([
            ('day_id.employee_id', '=', employee.id),
            ('day_id.date', '=', employee._ff_today()),
            ('partner_id', '=', partner.id),
            ('selected', '=', True),
        ])
        data.update(
            sites=[client_data(s) for s in sites],
            recent_visits=[visit_data(v) for v in visits],
            allow_orders=bool(partner.ff_category_id.allow_orders),
            planned_today=bool(planned),
        )
        return ok(data)

    @api_route('/api/v1/clients/<int:partner_id>/history', methods=('GET',))
    def client_history(self, employee, partner_id, limit=None, **kw):
        """What happened at this customer lately: visits, orders or demands, payments."""
        partner = visible_client(employee, partner_id)
        family = partner.commercial_partner_id
        size = min(to_int(limit) or 20, 100)
        env = request.env

        def label(record, field):
            return dict(record._fields[field]._description_selection(env)).get(record[field])

        visits = env['ff.visit'].sudo().search(
            [('partner_id', 'child_of', family.id)], order='check_in_at desc', limit=size)
        orders = env['sale.order'].sudo().search(
            [('partner_id', 'child_of', family.id)], order='date_order desc', limit=size)
        data = {
            'visits': [visit_data(v) for v in visits],
            'orders': [{
                'id': o.id, 'name': o.name, 'date': to_iso(o.date_order), 'amount': round(o.amount_total, 2),
                'currency': o.currency_id.name, 'state': o.state, 'state_label': label(o, 'state'),
                'employee': ref(o.ff_employee_id),
            } for o in orders],
            'demands': [],
            'collections': [],
        }
        if 'ff.demand' in env:
            demands = env['ff.demand'].sudo().search(
                [('partner_id', 'child_of', family.id)], order='date desc', limit=size)
            data['demands'] = [{
                'id': d.id, 'name': d.name, 'date': to_iso(d.date), 'amount': round(d.amount_total, 2),
                'currency': d.currency_id.name, 'state': d.state, 'state_label': label(d, 'state'),
                'employee': ref(d.employee_id), 'distributor': ref(d.distributor_id),
            } for d in demands]
        if 'ff.collection' in env:
            collections = env['ff.collection'].sudo().search(
                [('partner_id', 'child_of', family.id)], order='date desc', limit=size)
            data['collections'] = [{
                'id': c.id, 'date': to_iso(c.date), 'amount': round(c.amount, 2), 'currency': c.currency_id.name,
                'mode': c.mode_id.name, 'reference': c.reference or None, 'state': c.state,
                'state_label': label(c, 'state'), 'employee': ref(c.employee_id),
            } for c in collections]
        return ok(data)

    @api_route('/api/v1/clients/<int:partner_id>/balance', methods=('GET',))
    def client_balance(self, employee, partner_id, **kw):
        """What the customer owes: open invoices, how much is overdue, cash not yet deposited."""
        partner = visible_client(employee, partner_id)
        family = partner.commercial_partner_id
        env = request.env
        company = employee.company_id
        today = employee._ff_today()
        rows, due, overdue = [], 0.0, 0.0
        if 'account.move' in env:
            moves = env['account.move'].sudo().search([
                ('partner_id', 'child_of', family.id), ('move_type', 'in', ('out_invoice', 'out_refund')),
                ('state', '=', 'posted'), ('payment_state', 'in', ('not_paid', 'partial')),
                ('company_id', '=', company.id),
            ], order='invoice_date_due asc, id asc')
            for move in moves:
                # amount_residual_signed is in company currency, negative for refunds.
                residual = move.amount_residual_signed
                due += residual
                late = bool(move.invoice_date_due and move.invoice_date_due < today and residual > 0)
                if late:
                    overdue += residual
                rows.append({
                    'id': move.id, 'name': move.name, 'date': to_iso(move.invoice_date),
                    'due_date': to_iso(move.invoice_date_due), 'amount': round(move.amount_total_signed, 2),
                    'residual': round(residual, 2), 'overdue': late,
                    'days_overdue': (today - move.invoice_date_due).days if late else 0,
                })
        with_staff = 0.0
        if 'ff.collection' in env:
            pending = env['ff.collection'].sudo().search([
                ('partner_id', 'child_of', family.id), ('state', 'in', ('collected', 'submitted'))])
            with_staff = round(sum(pending.mapped('amount')), 2)
        return ok({
            'currency': company.currency_id.name,
            'due': round(due, 2),
            'overdue': round(overdue, 2),
            'credit_limit': round(family.credit_limit, 2) if 'credit_limit' in family._fields else 0.0,
            'collected_not_deposited': with_staff,
            'invoices': rows[:50],
        })

    @api_route('/api/v1/clients/<int:partner_id>/update', methods=('POST',))
    def update_client(self, employee, partner_id, **kw):
        """Correct a customer's contact details, or move its pin to where the employee stands."""
        partner = visible_client(employee, partner_id).sudo()
        data = body()
        if partner.ff_category_type == 'lead' and not getattr(employee.sudo(), 'ff_lead_edit', False):
            raise ApiError('You are not allowed to edit leads.', 403, 'forbidden')
        asking = request.env['ir.config_parameter'].sudo().get_param('ff_base.ask_missing_details') in (
            'True', 'true', '1')
        filling = asking and hasattr(partner, 'ff_onboard_missing') and bool(
            partner.ff_onboard_missing(partner.ff_category_type or 'outlet'))
        if getattr(partner, 'ff_status', None) == 'onboarded' and not getattr(employee, 'ff_edit_after_onboard', False) \
                and not filling:
            raise ApiError('This contact is onboarded. Only people allowed to edit onboarded contacts can change it.',
                           403, 'forbidden')
        vals = {}
        for field in ('phone', 'email', 'street', 'street2', 'city', 'zip'):
            if field in data:
                vals[field] = (data.get(field) or '').strip() or False
        if 'gst' in data:
            vals['vat'] = (data.get('gst') or '').strip().upper() or False
        if data.get('category_id'):
            category = category_for(employee, data['category_id'])
            vals['ff_category_id'] = category.id
            # Becoming a real customer means picking a beat for it.
            request.env['res.partner']._ff_check_beat(
                category, data.get('route_id') or partner.ff_route_ids)
        if data.get('district_id'):
            vals['ff_district_id'] = to_int(data['district_id']) or False
        if data.get('route_id'):
            route = request.env['ff.beat'].sudo().browse(to_int(data['route_id']) or []).exists()
            if not route or not request.env['ff.beat'].ff_can_use_beat(employee, route):
                raise ApiError('This route is not one of yours.', 403, 'forbidden')
            vals['ff_route_ids'] = [(4, route.id)]
            # Everybody who works that route can see the contact from now on.
            vals['ff_employee_ids'] = [(4, person.id) for person in route.employee_ids]
            # A route covers one city: take it unless the app sent one.
            if route.district_id and not vals.get('ff_district_id'):
                vals['ff_district_id'] = route.district_id.id
            if route.district_id and not data.get('city'):
                vals['city'] = route.district_id.name
        if (data.get('name') or '').strip():
            vals['name'] = data['name'].strip()
        notes = []
        if data.get('set_location'):
            lat, lng = to_float(data.get('lat')), to_float(data.get('lng'))
            if lat is None or lng is None:
                raise ApiError('Location is required to move the customer pin.')
            if data.get('mock'):
                raise ApiError('A fake GPS app was detected. Disable it to update the location.', 403, 'forbidden')
            old_lat, old_lng = partner.partner_latitude, partner.partner_longitude
            vals.update(partner_latitude=lat, partner_longitude=lng)
            if old_lat or old_lng:
                moved = int(haversine_m(old_lat, old_lng, lat, lng))
                notes.append('Location moved %d m by %s (was %.6f, %.6f).' % (moved, employee.name, old_lat, old_lng))
            else:
                notes.append('Location set by %s.' % employee.name)
        details = data.get('details')
        if isinstance(details, dict) and hasattr(partner, 'ff_update_details'):
            try:
                done = partner.ff_update_details(details)
            except ValidationError as error:
                request.env.cr.rollback()
                raise ApiError(str(error), 400, 'invalid')
            if done:
                notes.append('Onboarding details updated from the app by %s.' % employee.name)
        if not vals and not notes:
            raise ApiError('Nothing to change.')
        changed = [partner._fields[f].string for f in vals
                   if f in partner._fields and f not in ('partner_latitude', 'partner_longitude')]
        partner.write(vals)
        if changed:
            notes.insert(0, '%s updated from the app by %s.' % (', '.join(changed), employee.name))
        partner.message_post(body='<br/>'.join(notes))
        return ok(client_data(partner))

    @api_route('/api/v1/clients', methods=('POST',))
    def create_client(self, employee, **kw):
        data = body()
        name = (data.get('name') or '').strip()
        if not name:
            raise ApiError('Client name is required.')
        vals = {
            'name': name,
            'phone': data.get('phone') or False,
            'email': data.get('email') or False,
            'street': data.get('street') or False,
            'city': data.get('city') or False,
            'zip': data.get('zip') or False,
            'comment': data.get('note') or False,
            'partner_latitude': to_float(data.get('lat')) or 0.0,
            'partner_longitude': to_float(data.get('lng')) or 0.0,
            'vat': (data.get('gst') or '').strip().upper() or False,
            'ff_category_id': category_for(employee, data.get('category_id')).id,
            'ff_district_id': to_int(data.get('district_id')) or False,
        }
        # The territory and area the app suggested from the location (or the person chose).
        Partner = request.env['res.partner']
        if to_int(data.get('territory_id')) and 'ff_territory_id' in Partner._fields:
            vals['ff_territory_id'] = to_int(data['territory_id'])
        if to_int(data.get('area_id')) and 'ff_area_id' in Partner._fields:
            vals['ff_area_id'] = to_int(data['area_id'])
        # An outlet or a distributor needs a beat; a lead may wait for one.
        request.env['res.partner']._ff_check_beat(
            category_for(employee, data.get('category_id')), data.get('route_id'))
        if data.get('parent_id'):
            vals.update(parent_id=visible_client(employee, int(data['parent_id'])).id, type='other')
        if data.get('route_id'):
            route = request.env['ff.beat'].sudo().browse(to_int(data['route_id']) or []).exists()
            if not route or not request.env['ff.beat'].ff_can_use_beat(employee, route):
                raise ApiError('This route is not one of yours.', 403, 'forbidden')
            # The contact joins the route and is shared with everyone working it.
            vals['ff_route_ids'] = [(4, route.id)]
            vals['ff_extra_employee_ids'] = route.employee_ids.ids
            # A route covers one city: the customer takes it unless the app said otherwise.
            if route.district_id and not vals.get('ff_district_id'):
                vals['ff_district_id'] = route.district_id.id
            if route.district_id and not vals.get('city'):
                vals['city'] = route.district_id.name
            if route.state_id and not vals.get('state_id'):
                vals['state_id'] = route.state_id.id
            if route.country_id and not vals.get('country_id'):
                vals['country_id'] = route.country_id.id
        partner = request.env['res.partner'].ff_create_from_app(employee, vals)
        return ok(client_data(partner), status=201)

    @api_route('/api/v1/my-routes', methods=('GET',))
    def my_routes(self, employee, **kw):
        """The routes this person may use, to choose from when editing a contact.

        What the contact access rule allows - not every route the company has. A route still waiting
        for the office is here for whoever drew it; a turned-down one is here for nobody.
        """
        # The beats the contact access rule gives this person: the same list planning and check-in use.
        own = employee.sudo().ff_route_ids
        routes = request.env['ff.beat'].ff_beats_for(employee)
        routes = routes.sorted(lambda route: (route.display_name or '').lower())

        def usual_area(route):
            """The area most of the beat's outlets sit in, so choosing a beat can fill the area in."""
            Partner = request.env['res.partner']
            if 'ff_area_id' not in Partner._fields:
                return None
            counts = {}
            for area in route.line_ids.partner_id.mapped('ff_area_id'):
                counts[area] = sum(1 for p in route.line_ids.partner_id if p.ff_area_id == area)
            return ref(max(counts, key=counts.get)) if counts else None

        return ok([{
            'id': route.id,
            'name': route.name,
            'city': route.district_id.name or None,
            'district_id': route.district_id.id or None,
            'schedule': route.ff_schedule or None,
            'team_id': route.team_id.id or None,
            'territory_id': route.territory_id.id or None if 'territory_id' in route._fields else None,
            'territory': ref(route.territory_id) if 'territory_id' in route._fields else None,
            'area': usual_area(route),
            'approval_state': route.ff_approval_state,
        } for route in routes])

    @api_route('/api/v1/contact-categories', methods=('GET',))
    def contact_categories(self, employee, **kw):
        # The field only ever adds these; customer categories are treated as outlets
        categories = request.env['ff.contact.category'].ff_for_employee(employee).filtered(
            lambda c: c.category_type in ('lead', 'outlet', 'distributor', 'customer'))
        def _cat_type(c):
            ctype = c.category_type or ''
            cname = (c.name or '').lower()
            if ctype == 'distributor' or 'distributor' in cname:
                return 'distributor'
            if ctype == 'lead' or 'lead' in cname:
                return 'lead'
            return 'outlet'

        return ok([{
            'id': c.id,
            'name': c.name,
            'type': _cat_type(c),
            'allow_orders': c.allow_orders,
            'requires_approval': c.requires_approval,
        } for c in categories])

    @api_route('/api/v1/districts', methods=('GET',))
    def districts(self, employee, state_id=None, q=None, **kw):
        domain = []
        if state_id:
            domain.append(('state_id', '=', to_int(state_id)))
        if q:
            domain.append(('name', 'ilike', q))
        districts = request.env['ff.district'].sudo().search(domain, limit=200)
        return ok([{'id': d.id, 'name': d.name, 'state': ref(d.state_id), 'country': ref(d.country_id)}
                   for d in districts])
