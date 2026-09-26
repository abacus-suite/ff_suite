import math

from odoo import http
from odoo.http import request

from odoo.addons.ff_base.tools import haversine_m, to_iso

from .common import ApiError, api_route, body, ok, ref
from .field_data import client_data, visit_data

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
    return list(ids)


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
    if employee.ff_access_scope == 'all':
        domain = [('ff_is_client', '=', True), ('ff_approval_state', '!=', 'rejected')]
        # Somebody who sees everything only narrows down when they pick a person.
        if member not in ('team', 'me'):
            domain.append(('ff_employee_ids', 'in', people.ids))
        return domain
    if people == employee:
        return _with_routes(request.env['res.partner']._ff_visible_domain(employee), extra)
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


def _category_counts(employee, member=None):
    """How many contacts of each kind the person may see, for the chips."""
    Partner = request.env['res.partner'].sudo()
    base = client_domain(employee, member)
    groups = Partner._read_group(base, ['ff_category_id'], ['__count'])
    by_category = [{
        'id': category.id,
        'name': category.name,
        'type': category.category_type,
        'count': count,
    } for category, count in groups if category]
    by_category.sort(key=lambda row: -row['count'])
    return {'total': sum(row['count'] for row in by_category), 'categories': by_category}


class FieldForceClientsApi(http.Controller):

    @api_route('/api/v1/clients', methods=('GET',))
    def clients(self, employee, q=None, category_id=None, lat=None, lng=None, radius_km=None,
                limit=None, offset=None, member=None, **kw):
        Partner = request.env['res.partner'].sudo()
        domain = client_domain(employee, member)
        if q:
            domain += ['|', '|', '|', ('name', 'ilike', q), ('ff_client_code', 'ilike', q),
                       ('phone', 'ilike', q), ('city', 'ilike', q)]
        if category_id:
            domain.append(('ff_category_id', '=', to_int(category_id)))
        try:
            limit = min(int(limit or 50), MAX_LIMIT)
            offset = max(int(offset or 0), 0)
        except ValueError:
            raise ApiError('limit and offset must be numbers.')
        lat, lng = to_float(lat), to_float(lng)

        if lat is not None and lng is not None:
            radius = to_float(radius_km) or DEFAULT_RADIUS_KM
            dlat = radius / 111.0
            dlng = dlat / max(math.cos(math.radians(lat)), 0.2)
            domain += [('partner_latitude', '>=', lat - dlat), ('partner_latitude', '<=', lat + dlat),
                       ('partner_longitude', '>=', lng - dlng), ('partner_longitude', '<=', lng + dlng)]
            rows = [client_data(p, lat, lng) for p in Partner.search(domain)]
            rows = sorted((r for r in rows if r['distance_m'] <= radius * 1000), key=lambda r: r['distance_m'])
            return ok({'total': len(rows), 'counts': _category_counts(employee, member),
                       'clients': rows[offset:offset + limit]})

        total = Partner.search_count(domain)
        partners = Partner.search(domain, order='name', limit=limit, offset=offset)
        return ok({'total': total, 'counts': _category_counts(employee, member),
                   'clients': [client_data(p) for p in partners]})

    @api_route('/api/v1/clients/<int:partner_id>', methods=('GET',))
    def client(self, employee, partner_id, lat=None, lng=None, **kw):
        partner = visible_client(employee, partner_id)
        visits = request.env['ff.visit'].sudo().search([('partner_id', '=', partner.id)], limit=5)
        sites = partner.child_ids.filtered(lambda c: c.ff_is_client and c.ff_approval_state == 'approved')
        data = client_data(partner, to_float(lat), to_float(lng))
        data.update(
            sites=[client_data(s) for s in sites],
            recent_visits=[visit_data(v) for v in visits],
            allow_orders=bool(partner.ff_category_id.allow_orders),
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
        vals = {}
        for field in ('phone', 'email', 'street', 'street2', 'city', 'zip'):
            if field in data:
                vals[field] = (data.get(field) or '').strip() or False
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
        if not vals:
            raise ApiError('Nothing to change.')
        changed = [partner._fields[f].string for f in vals if f not in ('partner_latitude', 'partner_longitude')]
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
            'ff_category_id': category_for(employee, data.get('category_id')).id,
            'ff_district_id': to_int(data.get('district_id')) or False,
        }
        if data.get('parent_id'):
            vals.update(parent_id=visible_client(employee, int(data['parent_id'])).id, type='other')
        if data.get('route_id'):
            route = request.env['ff.beat'].sudo().browse(to_int(data['route_id']) or []).exists()
            if not route or (employee.ff_route_ids and route not in employee.ff_route_ids):
                raise ApiError('This route is not assigned to you.', 403, 'forbidden')
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

    @api_route('/api/v1/contact-categories', methods=('GET',))
    def contact_categories(self, employee, **kw):
        categories = request.env['ff.contact.category'].ff_for_employee(employee)
        return ok([{
            'id': c.id,
            'name': c.name,
            'type': c.category_type,
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
