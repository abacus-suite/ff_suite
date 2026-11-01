"""Builds the Field Force demo on install: a 3-level team, beats, customers and 10 days of history.

Everything is dated relative to the install day, so the dashboard, reports and
the app always have "today", "this week" and "this month" to show.
"""
import logging
import math
import random
from datetime import datetime, time, timedelta

import pytz

from odoo import fields

_logger = logging.getLogger(__name__)

PASSWORD = 'FieldForce@123'
TZ = 'Asia/Kolkata'
DAYS = 10
CENTRE = (11.2588, 75.7804)  # Kozhikode

PEOPLE = [
    # key, name, job, code, manager key, team key, scope, group
    ('head', 'Ravi Menon', 'Sales Head', 'AX-001', None, None, 'all', 'ff_base.group_ff_admin'),
    ('north', 'Anil Kumar', 'Area Manager - North', 'AX-011', 'head', 'north', 'hierarchy', 'ff_base.group_ff_manager'),
    ('south', 'Divya Nair', 'Area Manager - South', 'AX-012', 'head', 'south', 'hierarchy', 'ff_base.group_ff_manager'),
    ('rep1', 'Arjun Das', 'Sales Representative', 'AX-101', 'north', 'north', 'own', 'ff_base.group_ff_officer'),
    ('rep2', 'Fathima Rahman', 'Sales Representative', 'AX-102', 'north', 'north', 'own', 'ff_base.group_ff_officer'),
    ('rep3', 'Suresh Babu', 'Sales Representative', 'AX-103', 'south', 'south', 'own', 'ff_base.group_ff_officer'),
]
AREAS = ['Nadakkavu', 'Mavoor Road', 'Palayam', 'Beach Road', 'Eranhipalam', 'West Hill', 'Chevayur',
         'Kallai', 'Meenchanda', 'Feroke', 'Ramanattukara', 'Kunnamangalam', 'Balussery', 'Koyilandy', 'Vadakara']
SHOP_WORDS = ['Stores', 'Traders', 'Mart', 'Supermarket', 'Agencies', 'Medicals', 'Enterprises', 'Bazaar']
SHOP_NAMES = ['Anand', 'Sree Krishna', 'Malabar', 'Al Ameen', 'Royal', 'City', 'Green Leaf', 'Sahara', 'Jyothi',
              'Fresh Choice', 'Lakshmi', 'Noor', 'Galaxy', 'Deepam', 'Hilal']
PRODUCTS = [
    # name, sku, MRP, PTR, PTS
    ('ABS Soap 100g', 'SOAP100', 45, 38, 34),
    ('ABS Shampoo 180ml', 'SHMP180', 160, 132, 118),
    ('ABS Detergent 1kg', 'DET1KG', 120, 101, 92),
    ('ABS Toothpaste 150g', 'TP150', 95, 79, 71),
    ('ABS Hair Oil 200ml', 'OIL200', 140, 116, 104),
    ('ABS Handwash 250ml', 'HW250', 99, 82, 74),
    ('ABS Floor Cleaner 1L', 'FLR1L', 175, 146, 131),
    ('ABS Tea 250g', 'TEA250', 130, 109, 98),
]


def post_init_hook(env):
    random.seed(17)
    env = env(context=dict(env.context, tracking_disable=True, mail_create_nolog=True, mail_notrack=True))
    company = env.company
    env['ir.config_parameter'].sudo().set_param('ff_base.default_tz', TZ)
    env['ir.config_parameter'].sudo().set_param('ff_base.order_flow', 'demand')
    env['ir.config_parameter'].sudo().set_param('ff_base.payment_collection', 'True')
    env['ir.config_parameter'].sudo().set_param('ff_base.selfie_required', 'False')
    today = datetime.now(pytz.timezone(TZ)).date()

    people, teams, department = _people(env, company)
    products = _products(env)
    distributors, beats, customers = _territory(env, company, people)
    _history(env, people, beats, customers, products, distributors, today)
    _month_extras(env, company, people, teams, department, products, today)
    _logger.info('Field Force demo data created: %s employees, %s beats, %s customers',
                 len(people), len(beats), len(customers))


# ----------------------------------------------------------------------
def _people(env, company):
    department = env['hr.department'].create({'name': 'Field Sales (Demo)', 'company_id': company.id})
    teams = {
        'north': env['ff.team'].create({'name': 'Team North (Demo)', 'company_id': company.id}),
        'south': env['ff.team'].create({'name': 'Team South (Demo)', 'company_id': company.id}),
    }
    people = {}
    for key, name, job, code, manager, team, scope, group in PEOPLE:
        login = 'demo.%s' % key
        groups_field = 'group_ids' if 'group_ids' in env['res.users']._fields else 'groups_id'
        user = env['res.users'].with_context(no_reset_password=True).create({
            'name': name, 'login': login, 'password': PASSWORD, 'email': '%s@fieldforce.demo' % login,
            'tz': TZ, 'company_id': company.id, 'company_ids': [(6, 0, company.ids)],
            groups_field: [(4, env.ref('base.group_user').id), (4, env.ref(group).id)],
        })
        employee = user.employee_id or env['hr.employee'].create({'name': name, 'user_id': user.id})
        employee.write({
            'name': name, 'job_title': job, 'ff_employee_code': code, 'tz': TZ,
            'department_id': department.id, 'ff_access_scope': scope,
            'parent_id': people[manager].id if manager else False,
            'ff_team_id': teams[team].id if team else False,
            'work_email': '%s@fieldforce.demo' % login, 'mobile_phone': '+91 98470 %05d' % (len(people) * 1111),
            'ff_app_login': login,
        })
        employee.ff_set_app_password(PASSWORD)
        people[key] = employee
    teams['north'].manager_id = people['north']
    teams['south'].manager_id = people['south']
    department.manager_id = people['head']
    return people, teams, department


def _products(env):
    category = env['product.category'].create({'name': 'ABS FMCG (Demo)'})
    products = env['product.product']
    for name, sku, mrp, ptr, pts in PRODUCTS:
        products |= env['product.product'].create({
            'name': name, 'default_code': sku, 'ff_sku_code': sku, 'sale_ok': True, 'type': 'consu',
            'categ_id': category.id, 'lst_price': ptr, 'ff_mrp': mrp, 'ff_ptr': ptr, 'ff_pts': pts,
            'ff_show_in_app': True,
        })
    return products


def _point(index, spread=0.09):
    """A spot around the city centre, spread out so the map does not stack pins."""
    angle = index * 0.73
    radius = spread * (0.25 + (index % 7) / 8.0) * random.uniform(0.6, 1.0)
    return CENTRE[0] + radius * math.sin(angle), CENTRE[1] + radius * math.cos(angle)


def _territory(env, company, people):
    state = env['res.country.state'].search([('code', '=', 'KL'), ('country_id.code', '=', 'IN')], limit=1)
    district = env['ff.district'].create({'name': 'Kozhikode (Demo)', 'state_id': state.id}) if state else env['ff.district']
    customer_category = env.ref('ff_clients.contact_category_outlet', raise_if_not_found=False) \
        or env.ref('ff_clients.contact_category_customer')
    distributor_category = env.ref('ff_clients.contact_category_distributor', raise_if_not_found=False) or customer_category
    reps = [people['rep1'], people['rep2'], people['rep3']]
    field_team = reps + [people['north'], people['south']]

    distributors = env['res.partner']
    for name in ('Malabar Distributors (Demo)', 'Calicut Trade Links (Demo)'):
        lat, lng = _point(len(distributors) + 40, 0.03)
        distributors |= env['res.partner'].create({
            'name': name, 'is_company': True, 'city': 'Kozhikode', 'ff_is_client': True, 'ff_is_distributor': True,
            'ff_category_id': distributor_category.id, 'ff_approval_state': 'approved',
            'partner_latitude': lat, 'partner_longitude': lng, 'ff_employee_ids': [(6, 0, [e.id for e in field_team])],
        })

    route_type = env['ff.route.type'].search([], limit=1)
    beats, customers = env['ff.beat'], env['res.partner']
    for index, area in enumerate(AREAS):
        rep = reps[index % 3]
        beat_vals = {
            'name': area, 'code': 'B%02d' % (index + 1), 'company_id': company.id,
            'team_id': rep.ff_team_id.id, 'employee_ids': [(6, 0, [rep.id, rep.parent_id.id])],
            'ff_distributor_id': distributors[index % 2].id,
        }
        if district:
            beat_vals.update(district_id=district.id, state_id=district.state_id.id, country_id=district.country_id.id)
        if route_type:
            beat_vals['route_type_id'] = route_type.id
        beat = env['ff.beat'].create(beat_vals)
        lines = []
        for slot in range(2):
            number = index * 2 + slot
            lat, lng = _point(number)
            customer = env['res.partner'].create({
                'name': '%s %s' % (SHOP_NAMES[(index + slot * 7) % len(SHOP_NAMES)], SHOP_WORDS[number % len(SHOP_WORDS)]),
                'is_company': True, 'street': area, 'city': 'Kozhikode', 'zip': '6730%02d' % (number % 99),
                'phone': '+91 495 27%05d' % (number * 37), 'ff_is_client': True, 'ff_client_code': 'C%03d' % (number + 1),
                'ff_category_id': customer_category.id, 'ff_approval_state': 'approved',
                'ff_district_id': district.id if district else False,
                'partner_latitude': lat, 'partner_longitude': lng,
                'ff_employee_ids': [(6, 0, [rep.id, rep.parent_id.id])],
                'ff_distributor_id': distributors[index % 2].id,
                'ff_created_by_employee_id': rep.id,
            })
            customers |= customer
            lines.append((0, 0, {'partner_id': customer.id, 'sequence': slot + 1}))
        beat.write({'line_ids': lines})
        beats |= beat
        rep.ff_route_ids = [(4, beat.id)]
        rep.parent_id.ff_route_ids = [(4, beat.id)]
    return distributors, beats, customers


def _utc(day, hour, minute=0):
    local = pytz.timezone(TZ).localize(datetime.combine(day, time(hour, minute)))
    return local.astimezone(pytz.utc).replace(tzinfo=None)


def _history(env, people, beats, customers, products, distributors, today):
    reps = [people['rep1'], people['rep2'], people['rep3']]
    modes = env['ff.collection.mode'].search([])
    cash = modes.filtered(lambda m: m.mode_type == 'cash')[:1] or modes[:1]
    online = modes.filtered(lambda m: m.mode_type == 'online')[:1] or cash
    cheque = modes.filtered(lambda m: m.mode_type == 'cheque')[:1] or cash
    expense_types = env['ff.expense.category'].search([])
    outcome = env['ff.visit.outcome'].search([('is_order', '=', True)], limit=1)
    counter = 0

    for back in range(DAYS - 1, -1, -1):
        day = today - timedelta(days=back)
        if day.weekday() == 6:  # Sunday off
            continue
        everyone = list(people.values())
        for employee in everyone:
            if back == 3 and employee == people['rep2']:
                continue  # one absence to show on the calendar
            start_minute = random.choice([0, 5, 15, 25, 40])
            check_in = _utc(day, 9, start_minute)
            still_on = back == 0
            env['hr.attendance'].create({
                'employee_id': employee.id, 'check_in': check_in,
                'check_out': False if still_on else _utc(day, 18, random.choice([0, 10, 30])),
                'in_latitude': CENTRE[0], 'in_longitude': CENTRE[1], 'ff_source': 'app',
                'ff_in_address': 'Nadakkavu, Kozhikode',
            })

        for rep_index, rep in enumerate(reps):
            if back == 3 and rep == people['rep2']:
                continue
            my_beats = beats.filtered(lambda b, rep=rep: rep in b.employee_ids)
            beat = my_beats[(DAYS - back + rep_index) % len(my_beats)]
            plan = env['ff.beat.plan'].create({
                'employee_id': rep.id, 'beat_id': beat.id, 'date': day,
                'customer_line_ids': [(0, 0, {'partner_id': line.partner_id.id, 'sequence': line.sequence})
                                      for line in beat.line_ids],
            })
            hour = 10
            for line in plan.customer_line_ids:
                partner = line.partner_id
                if back == 0 and hour > 11:
                    break  # today is still under way
                if random.random() < 0.15:
                    continue  # a missed call on the plan
                counter += 1
                offsite = counter % 9 == 0
                arrive = _utc(day, hour, random.randint(0, 30))
                leave = arrive + timedelta(minutes=random.randint(12, 35))
                open_visit = back == 0 and hour == 11
                visit = env['ff.visit'].create({
                    'employee_id': rep.id, 'partner_id': partner.id, 'check_in_at': arrive,
                    'check_out_at': False if open_visit else leave, 'state': 'ongoing' if open_visit else 'done',
                    'check_in_lat': partner.partner_latitude + (0.02 if offsite else 0.0003),
                    'check_in_lng': partner.partner_longitude, 'distance_m': 2200 if offsite else 35,
                    'inside_geofence': not offsite, 'visit_type': 'offsite' if offsite else 'onsite',
                    'offsite_reason': 'Met the owner at the market' if offsite else False,
                    'outcome_id': outcome.id if outcome else False, 'beat_plan_id': plan.id,
                })
                line.visit_id = visit.id
                hour += 1
                if open_visit:
                    continue
                # Demand at most calls
                if random.random() < 0.8:
                    chosen = random.sample(list(products), random.randint(2, 4))
                    demand = env['ff.demand'].create({
                        'employee_id': rep.id, 'partner_id': partner.id, 'visit_id': visit.id,
                        'distributor_id': partner.ff_distributor_id.id, 'route_id': beat.id,
                        'date': arrive + timedelta(minutes=8),
                        'line_ids': [(0, 0, {'product_id': product.id, 'quantity': random.choice([6, 10, 12, 20, 24]),
                                             'price_unit': product.ff_ptr}) for product in chosen],
                    })
                    if back >= 6:
                        demand.state = 'quoted'
                # Collection at some
                if random.random() < 0.45:
                    mode = random.choice([cash, cash, online, cheque])
                    amount = random.choice([1500, 2400, 3200, 4750, 6000, 8200])
                    env['ff.collection'].create({
                        'employee_id': rep.id, 'partner_id': partner.id, 'visit_id': visit.id, 'mode_id': mode.id,
                        'amount': amount, 'date': arrive + timedelta(minutes=15),
                        'reference': ('UTR%08d' % counter) if mode == online else ('CHQ%06d' % counter) if mode == cheque else False,
                        'state': ('received' if back >= 5 else 'collected') if mode.needs_deposit else 'received',
                        'latitude': partner.partner_latitude, 'longitude': partner.partner_longitude,
                    })
            if expense_types and back in (1, 4, 7):
                claim = env['ff.expense.claim'].create({
                    'employee_id': rep.id, 'date': day, 'category_id': expense_types[back % len(expense_types)].id,
                    'amount': random.choice([120, 180, 250, 340]), 'note': 'Demo expense',
                })
                if back >= 4 and hasattr(claim, 'action_submit'):
                    try:
                        claim.action_submit()
                    except Exception:  # noqa: BLE001 - demo stays useful even if a flow refuses
                        _logger.info('Demo expense left as draft')

        # A distance for the day, so reports and the timeline have kilometres
        for rep in reps:
            if back == 3 and rep == people['rep2']:
                continue
            env['ff.daily.track'].create({
                'employee_id': rep.id, 'date': day, 'distance_km': round(random.uniform(18, 46), 1),
                'ping_count': random.randint(120, 260), 'first_ping_at': _utc(day, 9, 10),
                'last_ping_at': _utc(day, 12 if back == 0 else 18, 0),
            })

    # Today: who is on duty and where they are
    for index, rep in enumerate(reps):
        lat, lng = _point(index + 3, 0.05)
        status = env['ff.employee.status']._ff_get(rep)
        status.write({'punched_in': True, 'punched_in_at': _utc(today, 9, 5), 'last_ping_at': fields.Datetime.now(),
                      'latitude': lat, 'longitude': lng, 'battery': [78, 54, 19][index], 'gps_on': True,
                      'moved_at': fields.Datetime.now()})
    for key in ('head', 'north', 'south'):
        env['ff.employee.status']._ff_get(people[key]).write({'punched_in': True, 'punched_in_at': _utc(today, 9, 0)})


def _month_extras(env, company, people, teams, department, products, today):
    month = today.replace(day=1)
    Target = env['ff.target']
    rule = env['ff.incentive.rule'].create({
        'name': 'Monthly bonus (Demo)', 'condition': 'pro_rata', 'threshold_pct': 70, 'cap_pct': 120,
        'visit_amount': 1000, 'sales_amount': 3000, 'collection_amount': 2000,
    })
    top = Target.create({'scope': 'department', 'department_id': department.id, 'month': month,
                         'visit_target': 400, 'sales_target': 900000, 'collection_target': 300000,
                         'incentive_rule_id': rule.id})
    top.ff_split(None, [
        {'scope': 'team', 'id': teams['north'].id, 'visits': 260, 'sales': 600000, 'collections': 200000},
        {'scope': 'team', 'id': teams['south'].id, 'visits': 140, 'sales': 300000, 'collections': 100000},
    ])
    north = top.child_ids.filtered(lambda t: t.team_id == teams['north'])
    south = top.child_ids.filtered(lambda t: t.team_id == teams['south'])
    north.ff_split(people['north'], [
        {'scope': 'employee', 'id': people['rep1'].id, 'visits': 130, 'sales': 320000, 'collections': 110000},
        {'scope': 'employee', 'id': people['rep2'].id, 'visits': 110, 'sales': 250000, 'collections': 80000},
    ])
    south.ff_split(people['south'], [
        {'scope': 'employee', 'id': people['rep3'].id, 'visits': 130, 'sales': 280000, 'collections': 90000},
    ])

    env['ff.foc.scheme'].create({
        'name': 'Soap 10 + 1 (Demo)', 'product_ids': [(6, 0, products[:1].ids)], 'repeat': True,
        'slab_ids': [(0, 0, {'min_qty': 10, 'free_qty': 1})], 'note': 'Every 10 soaps, one free',
    })
    env['ff.foc.scheme'].create({
        'name': 'Shampoo slab (Demo)', 'product_ids': [(6, 0, products[1:2].ids)],
        'slab_ids': [(0, 0, {'min_qty': 12, 'free_qty': 1}), (0, 0, {'min_qty': 24, 'free_qty': 3})],
    })

    Task = env['ff.task']
    Task.create({'name': 'Put up the monsoon offer poster', 'employee_id': people['rep1'].id,
                 'date_deadline': today + timedelta(days=2), 'priority': '1', 'requires_photo': True,
                 'assigned_by_employee_id': people['north'].id})
    Task.create({'name': 'Collect pending cheque from Royal Traders', 'employee_id': people['rep3'].id,
                 'date_deadline': today - timedelta(days=1), 'priority': '2',
                 'assigned_by_employee_id': people['south'].id})
    Task.create({'name': 'Check shelf stock of shampoo', 'employee_id': people['rep2'].id,
                 'date_deadline': today, 'assigned_by_employee_id': people['north'].id})
