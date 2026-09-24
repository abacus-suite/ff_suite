"""South India demo: 30 people in 4 levels across Tamil Nadu, Kerala and Bangalore.

Each part is built inside its own savepoint, so a module that refuses one kind
of record (a stricter flow, a missing optional app) leaves the rest of the demo
in place. Dates are relative to the install day.
"""
import logging
import math
import random
import uuid
from datetime import date, datetime, time, timedelta

import pytz

from odoo import fields

_logger = logging.getLogger(__name__)

PASSWORD = 'FieldForce@123'
TZ = 'Asia/Kolkata'
DAYS = 7
DOMAIN = 'fieldforce.demo'

STATES = {
    # key: (state code, state name, manager name, team name)
    'tn': ('TN', 'Tamil Nadu', 'Karthik Raman', 'Tamil Nadu Region'),
    'kl': ('KL', 'Kerala', 'Meera Pillai', 'Kerala Region'),
    'ka': ('KA', 'Karnataka', 'Prakash Gowda', 'Karnataka Region'),
}
AREAS = [
    # key, state, city, centre, area manager, localities
    ('chn', 'tn', 'Chennai', (13.0827, 80.2707), 'Senthil Kumar',
     ['T. Nagar', 'Adyar', 'Anna Nagar', 'Velachery', 'Mylapore', 'Tambaram', 'Porur', 'Guindy', 'Egmore', 'Royapettah']),
    ('cbe', 'tn', 'Coimbatore', (11.0168, 76.9558), 'Lakshmi Narayanan',
     ['Gandhipuram', 'RS Puram', 'Peelamedu', 'Saibaba Colony', 'Singanallur', 'Ukkadam', 'Town Hall', 'Kuniyamuthur',
      'Vadavalli', 'Saravanampatti']),
    ('koc', 'kl', 'Kochi', (9.9312, 76.2673), 'Joseph Mathew',
     ['Edappally', 'Kakkanad', 'Vyttila', 'Palarivattom', 'Kaloor', 'Fort Kochi', 'Aluva', 'Tripunithura',
      'Marine Drive', 'Kadavanthra']),
    ('tvm', 'kl', 'Thiruvananthapuram', (8.5241, 76.9366), 'Anjali Nair',
     ['Pattom', 'Kowdiar', 'Vazhuthacaud', 'Kazhakkoottam', 'Sreekaryam', 'Palayam', 'Thampanoor', 'Kesavadasapuram',
      'Ulloor', 'Peroorkada']),
    ('bln', 'ka', 'Bangalore North', (13.0358, 77.5970), 'Ravi Shankar',
     ['Hebbal', 'Yelahanka', 'RT Nagar', 'Malleshwaram', 'Rajajinagar', 'Yeshwanthpur', 'Sahakar Nagar', 'Jalahalli',
      'Banaswadi', 'HBR Layout']),
    ('bls', 'ka', 'Bangalore South', (12.9121, 77.6446), 'Divya Hegde',
     ['Koramangala', 'HSR Layout', 'BTM Layout', 'Jayanagar', 'JP Nagar', 'Bannerghatta Road', 'Electronic City',
      'Banashankari', 'Indiranagar', 'Whitefield']),
]
REPS = [
    # name, gender, area key
    ('Arun Prakash', 'male', 'chn'), ('Priya Dharshini', 'female', 'chn'), ('Vignesh Kumar', 'male', 'chn'),
    ('Kavya Sundar', 'female', 'chn'),
    ('Manoj Kumar', 'male', 'cbe'), ('Deepika Ramesh', 'female', 'cbe'), ('Sathish Babu', 'male', 'cbe'),
    ('Nikhil Varghese', 'male', 'koc'), ('Aswathy Menon', 'female', 'koc'), ('Rahul Krishnan', 'male', 'koc'),
    ('Sreeja Suresh', 'female', 'tvm'), ('Akhil Raj', 'male', 'tvm'), ('Gopika Anil', 'female', 'tvm'),
    ('Kiran Kumar', 'male', 'bln'), ('Pooja Rao', 'female', 'bln'), ('Naveen Reddy', 'male', 'bln'),
    ('Shreya Iyer', 'female', 'bls'), ('Abhishek Shetty', 'male', 'bls'), ('Sneha Patil', 'female', 'bls'),
    ('Mohammed Irfan', 'male', 'bls'),
]
SHOP_NAMES = ['Sri Murugan', 'Annapoorna', 'Saravana', 'Kerala', 'Namma', 'Sree Durga', 'Lulu', 'Grace', 'Nilgiris',
              'Vasantham', 'Karnataka', 'Ganesh', 'Hari Om', 'Amma', 'Welcome']
SHOP_WORDS = ['Stores', 'Supermarket', 'Traders', 'Provisions', 'Mart', 'Medicals', 'Agencies', 'Hypermarket']
PRODUCTS = [
    ('ABS Soap 100g', 'SOAP100', 45, 38, 34), ('ABS Shampoo 180ml', 'SHMP180', 160, 132, 118),
    ('ABS Detergent 1kg', 'DET1KG', 120, 101, 92), ('ABS Toothpaste 150g', 'TP150', 95, 79, 71),
    ('ABS Hair Oil 200ml', 'OIL200', 140, 116, 104), ('ABS Handwash 250ml', 'HW250', 99, 82, 74),
    ('ABS Floor Cleaner 1L', 'FLR1L', 175, 146, 131), ('ABS Tea 250g', 'TEA250', 130, 109, 98),
    ('ABS Coffee 200g', 'COF200', 220, 186, 170), ('ABS Biscuits 300g', 'BIS300', 60, 50, 45),
]


def _step(env, label, fn, *args):
    """Run one part of the demo in a savepoint; a refusal is logged, not fatal."""
    try:
        with env.cr.savepoint():
            return fn(*args)
    except Exception:  # noqa: BLE001 - a demo part that fails must not stop the install
        _logger.exception('South India demo: %s skipped', label)
        return None


def post_init_hook(env):
    random.seed(29)
    env = env(context=dict(env.context, tracking_disable=True, mail_create_nolog=True, mail_notrack=True))
    params = env['ir.config_parameter'].sudo()
    params.set_param('ff_base.default_tz', TZ)
    params.set_param('ff_base.order_flow', 'demand')
    params.set_param('ff_base.payment_collection', 'True')
    params.set_param('ff_base.visit_steps', 'True')
    params.set_param('ff_base.stock_count', 'True')
    today = datetime.now(pytz.timezone(TZ)).date()
    ctx = Demo(env, today)
    ctx.build()


class Demo:
    def __init__(self, env, today):
        self.env = env
        self.today = today
        self.company = env.company
        self.people = {}       # key -> employee
        self.level = {}        # key -> 1..4
        self.area_of = {}      # key -> area key
        self.teams = {}
        self.customers = {}    # area key -> partners
        self.beats = {}        # area key -> beats
        self.distributors = {}

    # ------------------------------------------------------------------
    def build(self):
        env = self.env
        self.department = env['hr.department'].create({'name': 'South India Sales (Demo)', 'company_id': self.company.id})
        self.shift = _step(env, 'shift', self._shift) or env['ff.shift']
        self.designations = _step(env, 'designations', self._designations) or {}
        self.policy = _step(env, 'allowance policy', self._policy)
        self.products = self._products()
        self._people()
        _step(env, 'territory', self._territory)
        _step(env, 'devices', self._devices)
        _step(env, 'forms and visit steps', self._forms_and_steps)
        _step(env, 'history', self._history)
        _step(env, 'monthly route plans', self._route_plans)
        _step(env, 'route distances', self._route_distances)
        _step(env, 'returns', self._returns)
        _step(env, 'deposits', self._deposits)
        _step(env, 'allowance claims', self._allowance_claims)
        _step(env, 'regularisations', self._regularisations)
        _step(env, 'leaves', self._leaves)
        _step(env, 'targets', self._targets)
        _step(env, 'tasks', self._tasks)
        _step(env, 'alerts', self._alerts)
        _step(env, 'notifications', self._notifications)
        _step(env, 'compliance log', self._compliance)
        _step(env, 'live status', self._live_status)
        _logger.info('South India demo created: %s employees, %s customers', len(self.people),
                     sum(len(c) for c in self.customers.values()))

    # ------------------------------------------------------------------
    def _shift(self):
        return self.env['ff.shift'].create({
            'name': 'South Field Shift (9:30 - 18:30)', 'start_time': 9.5, 'end_time': 18.5, 'grace_minutes': 15,
            'half_day_hours': 4.0, 'off_sun': True, 'company_id': self.company.id,
        })

    def _designations(self):
        Designation = self.env['ff.designation']
        out = {}
        for level, name in ((1, 'Sales Executive'), (2, 'Area Sales Manager'), (3, 'State Sales Manager'),
                            (4, 'National Sales Head')):
            out[level] = Designation.search([('name', '=', name)], limit=1) or Designation.create(
                {'name': name, 'level': level})
        return out

    def _policy(self):
        return self.env['ff.allowance.policy'].create({
            'name': 'Two-wheeler TA (South Demo)', 'basis': 'gps', 'vehicle_type': 'two_wheeler',
            'rate_per_km': 3.5, 'road_factor': 1.3, 'max_km_per_day': 120, 'company_id': self.company.id,
            'department_ids': [(6, 0, self.department.ids)],
        })

    def _products(self):
        Product = self.env['product.product']
        category = self.env['product.category'].search([('name', '=', 'ABS FMCG (Demo)')], limit=1) or \
            self.env['product.category'].create({'name': 'ABS FMCG (Demo)'})
        products = Product
        for name, sku, mrp, ptr, pts in PRODUCTS:
            found = Product.search([('default_code', '=', sku)], limit=1)
            products |= found or Product.create({
                'name': name, 'default_code': sku, 'ff_sku_code': sku, 'sale_ok': True, 'type': 'consu',
                'categ_id': category.id, 'lst_price': ptr, 'ff_mrp': mrp, 'ff_ptr': ptr, 'ff_pts': pts,
                'ff_show_in_app': True,
            })
        return products

    # ------------------------------------------------------------------
    def _people(self):
        env = self.env
        Team = env['ff.team']
        self.teams['head'] = Team.create({'name': 'South India (Demo)', 'code': 'SIN', 'company_id': self.company.id})
        self._person('head', 'Venkatesh Iyer', 'male', 1, None, 'head', 'all', 'ff_base.group_ff_admin',
                     'National Sales Head', (12.9716, 77.5946), 'Bengaluru', 'KA')
        for key, (code, state_name, manager, team_name) in STATES.items():
            self.teams[key] = Team.create({'name': '%s (Demo)' % team_name, 'code': code,
                                           'parent_id': self.teams['head'].id, 'company_id': self.company.id})
            centre = next(a[3] for a in AREAS if a[1] == key)
            city = next(a[2] for a in AREAS if a[1] == key)
            self._person(key, manager, 'female' if manager in ('Meera Pillai',) else 'male', 2, 'head', key,
                         'hierarchy', 'ff_base.group_ff_manager', 'State Sales Manager - %s' % state_name,
                         centre, city.replace(' North', '').replace(' South', ''), code)
        for key, state, city, centre, manager, _localities in AREAS:
            self.teams[key] = Team.create({'name': '%s Area (Demo)' % city, 'code': key.upper(),
                                           'parent_id': self.teams[state].id, 'company_id': self.company.id})
            self._person(key, manager, 'female' if manager in ('Lakshmi Narayanan', 'Anjali Nair', 'Divya Hegde') else 'male',
                         3, state, key, 'hierarchy', 'ff_base.group_ff_manager', 'Area Sales Manager - %s' % city,
                         centre, city.replace(' North', '').replace(' South', ''), STATES[state][0])
            self.area_of[key] = key
        for index, (name, gender, area) in enumerate(REPS, start=1):
            key = 'rep%02d' % index
            state = next(a[1] for a in AREAS if a[0] == area)
            centre = next(a[3] for a in AREAS if a[0] == area)
            city = next(a[2] for a in AREAS if a[0] == area)
            self._person(key, name, gender, 4, area, area, 'own', None, 'Sales Executive', centre,
                         city.replace(' North', '').replace(' South', ''), STATES[state][0])
            self.area_of[key] = area
        for key, team in self.teams.items():
            team.manager_id = self.people[key]
        self.department.manager_id = self.people['head']

    def _person(self, key, name, gender, level, manager, team, scope, group, job, centre, city, state_code):
        env = self.env
        login = 'sin.%s' % key
        number = len(self.people) + 1
        user = env['res.users']
        if group:
            groups_field = 'group_ids' if 'group_ids' in env['res.users']._fields else 'groups_id'
            user = env['res.users'].with_context(no_reset_password=True).create({
                'name': name, 'login': login, 'password': PASSWORD, 'email': '%s@%s' % (login, DOMAIN), 'tz': TZ,
                'company_id': self.company.id, 'company_ids': [(6, 0, self.company.ids)],
                groups_field: [(4, env.ref('base.group_user').id), (4, env.ref(group).id)],
            })
        employee = user.employee_id if user else env['hr.employee']
        if not employee:
            employee = env['hr.employee'].create({'name': name, 'user_id': user.id if user else False,
                                                  'company_id': self.company.id})
        state = env['res.country.state'].search([('code', '=', state_code), ('country_id.code', '=', 'IN')], limit=1)
        india = env.ref('base.in')
        birthday = date(1978 + (number * 7) % 22, (number % 12) + 1, (number * 3) % 27 + 1)
        values = {
            'name': name, 'job_title': job, 'tz': TZ, 'company_id': self.company.id,
            'department_id': self.department.id,
            'parent_id': self.people[manager].id if manager else False,
            'coach_id': self.people[manager].id if manager else False,
            'ff_employee_code': 'SIN-%03d' % number,
            'ff_team_id': self.teams[team].id,
            'ff_designation_id': self.designations.get({1: 4, 2: 3, 3: 2, 4: 1}[level]).id if self.designations else False,
            'ff_access_scope': scope,
            'ff_tracking_enabled': True,
            'ff_app_access': True,
            'ff_app_login': login,
            'ff_shift_id': self.shift.id,
            'ff_allowance_policy_id': self.policy.id if self.policy else False,
            'ff_routes_per_day': 'multiple' if level <= 3 else 'single',
            'work_email': '%s@%s' % (login, DOMAIN),
            'mobile_phone': '+91 9%04d %05d' % (4000 + number * 13, 10000 + number * 377),
            'work_phone': '+91 80 4%03d %04d' % (number, 1000 + number * 9),
            'gender': gender,
            'birthday': birthday,
            'place_of_birth': city,
            'marital': 'married' if number % 3 else 'single',
            'children': number % 3,
            'private_street': '%d, %s Main Road' % (10 + number, city),
            'private_city': city,
            'private_state_id': state.id if state else False,
            'private_country_id': india.id,
            'private_zip': '%d' % (600001 + number * 11 if state_code == 'TN' else 682001 + number * 7
                                    if state_code == 'KL' else 560001 + number * 5),
            'private_email': '%s.personal@%s' % (login.replace('.', '_'), DOMAIN),
            'private_phone': '+91 9%04d %05d' % (5000 + number * 17, 20000 + number * 211),
            'emergency_contact': 'Family of %s' % name.split()[0],
            'emergency_phone': '+91 9%04d %05d' % (6000 + number * 19, 30000 + number * 101),
            'identification_id': 'EMP%06d' % (230000 + number),
            'km_home_work': 4 + number % 18,
            'country_id': india.id,
            'employee_type': 'employee',
            'lang': 'en_US',
        }
        employee.write({k: v for k, v in values.items() if k in employee._fields and v is not None})
        employee.ff_set_app_password(PASSWORD)
        self.people[key] = employee
        self.level[key] = level
        return employee

    def centre(self, key):
        area = self.area_of.get(key)
        if area:
            return next(a[3] for a in AREAS if a[0] == area)
        if key in STATES:
            return next(a[3] for a in AREAS if a[1] == key)
        return (12.9716, 77.5946)

    # ------------------------------------------------------------------
    def _territory(self):
        env = self.env
        customer_category = env.ref('ff_clients.contact_category_outlet', raise_if_not_found=False) \
            or env.ref('ff_clients.contact_category_customer')
        distributor_category = env.ref('ff_clients.contact_category_distributor', raise_if_not_found=False) \
            or customer_category
        route_type = env['ff.route.type'].search([], limit=1)
        number = 0
        for key, state_key, city, centre, _manager, localities in AREAS:
            state = env['res.country.state'].search([('code', '=', STATES[state_key][0]),
                                                     ('country_id.code', '=', 'IN')], limit=1)
            district = env['ff.district'].create({'name': '%s (Demo)' % city, 'state_id': state.id}) \
                if state else env['ff.district']
            area_people = [e for k, e in self.people.items() if self.area_of.get(k) == key]
            reps = [e for k, e in self.people.items() if self.area_of.get(k) == key and self.level[k] == 4]
            distributor = env['res.partner'].create({
                'name': '%s Distributors (Demo)' % city, 'is_company': True, 'city': city,
                'state_id': state.id if state else False, 'country_id': env.ref('base.in').id,
                'ff_is_client': True, 'ff_is_distributor': True, 'ff_category_id': distributor_category.id,
                'ff_approval_state': 'approved', 'partner_latitude': centre[0] + 0.01,
                'partner_longitude': centre[1] - 0.01, 'phone': '+91 44 2%03d %04d' % (number, 5000 + number),
                'email': 'orders.%s@%s' % (key, DOMAIN), 'ff_employee_ids': [(6, 0, [e.id for e in area_people])],
            })
            self.distributors[key] = distributor
            beats, customers = env['ff.beat'], env['res.partner']
            for beat_index in range(2):
                rep_set = reps[beat_index::2] or reps
                beat_vals = {
                    'name': '%s Route %s' % (city, 'A' if beat_index == 0 else 'B'),
                    'code': '%s-%s' % (key.upper(), 'A' if beat_index == 0 else 'B'), 'company_id': self.company.id,
                    'team_id': self.teams[key].id, 'employee_ids': [(6, 0, [e.id for e in area_people])],
                    'ff_distributor_id': distributor.id,
                }
                if district:
                    beat_vals.update(district_id=district.id, state_id=district.state_id.id,
                                     country_id=district.country_id.id)
                if route_type:
                    beat_vals['route_type_id'] = route_type.id
                beat = env['ff.beat'].create(beat_vals)
                lines = []
                for slot in range(5):
                    locality = localities[beat_index * 5 + slot]
                    angle = number * 0.9
                    radius = 0.018 + (number % 5) * 0.007
                    lat, lng = centre[0] + radius * math.sin(angle), centre[1] + radius * math.cos(angle)
                    owner = random.choice(reps or area_people)
                    customer = env['res.partner'].create({
                        'name': '%s %s' % (SHOP_NAMES[number % len(SHOP_NAMES)], SHOP_WORDS[(number * 3) % len(SHOP_WORDS)]),
                        'is_company': True, 'street': '%d, %s' % (5 + number, locality), 'street2': locality,
                        'city': city.replace(' North', '').replace(' South', ''),
                        'state_id': state.id if state else False, 'country_id': env.ref('base.in').id,
                        'zip': '%06d' % ((600010 if state_key == 'tn' else 682010 if state_key == 'kl' else 560010) + number),
                        'phone': '+91 9%04d %05d' % (7000 + number * 7, 40000 + number * 91),
                        'mobile': '+91 8%04d %05d' % (3000 + number * 5, 50000 + number * 77),
                        'email': 'shop%03d@%s' % (number + 1, DOMAIN),
                        'vat': '33AAAC%05dZ1Z%d' % (number, number % 9) if state_key == 'tn' else False,
                        'ff_is_client': True, 'ff_client_code': 'SIN-C%03d' % (number + 1),
                        'ff_category_id': customer_category.id, 'ff_approval_state': 'approved',
                        'ff_district_id': district.id if district else False,
                        'ff_geofence_radius': 150, 'partner_latitude': lat, 'partner_longitude': lng,
                        'ff_employee_ids': [(6, 0, [e.id for e in area_people])],
                        'ff_team_ids': [(6, 0, self.teams[key].ids)],
                        'ff_distributor_id': distributor.id, 'ff_created_by_employee_id': owner.id,
                    })
                    customers |= customer
                    lines.append((0, 0, {'partner_id': customer.id, 'sequence': slot + 1}))
                    number += 1
                beat.write({'line_ids': lines})
                beats |= beat
                for person in area_people:
                    person.ff_route_ids = [(4, beat.id)]
            # managers above can plan these routes too
            for person_key in (state_key, 'head'):
                self.people[person_key].ff_route_ids = [(4, b.id) for b in beats]
            self.beats[key] = beats
            self.customers[key] = customers

    def _devices(self):
        models = ['Samsung Galaxy M34', 'Redmi Note 13', 'Realme 12 Pro', 'Vivo T3', 'OnePlus Nord CE4', 'Poco X6']
        for index, (key, employee) in enumerate(self.people.items()):
            self.env['ff.device'].create({
                'employee_id': employee.id, 'name': models[index % len(models)],
                'device_uid': str(uuid.UUID(int=random.getrandbits(128))),
                'os_version': 'Android %d' % (13 + index % 3), 'app_version': '0.3.0+3',
                'last_seen': fields.Datetime.now() - timedelta(minutes=5 + index * 7),
            })

    # ------------------------------------------------------------------
    def _forms_and_steps(self):
        env = self.env
        Form = env['ff.form']
        self.shelf_form = Form.create({
            'name': 'Shelf audit (South Demo)', 'trigger': 'visit', 'frequency': 'visit', 'at_checkout': True,
            'description': 'Quick look at our shelf space at the outlet.',
            'field_ids': [
                (0, 0, {'name': 'Shelf share of our brand (%)', 'key': 'shelf_share', 'field_type': 'number',
                        'required': True, 'min_value': 0, 'max_value': 100}),
                (0, 0, {'name': 'Competitor running an offer?', 'key': 'competitor_offer', 'field_type': 'checkbox'}),
                (0, 0, {'name': 'Display condition', 'key': 'display', 'field_type': 'select',
                        'options': 'Good\nAverage\nPoor'}),
                (0, 0, {'name': 'Outlet rating', 'key': 'rating', 'field_type': 'rating'}),
                (0, 0, {'name': 'Remarks', 'key': 'remarks', 'field_type': 'textarea'}),
            ],
        })
        self.feedback_form = Form.create({
            'name': 'Market feedback (South Demo)', 'trigger': 'standalone', 'frequency': 'any',
            'field_ids': [
                (0, 0, {'name': 'Area', 'key': 'area', 'field_type': 'text', 'required': True}),
                (0, 0, {'name': 'Demand trend', 'key': 'trend', 'field_type': 'select',
                        'options': 'Rising\nSteady\nFalling'}),
                (0, 0, {'name': 'Notes', 'key': 'notes', 'field_type': 'textarea'}),
            ],
        })
        Step = env['ff.visit.step']
        self.steps = Step.search([('company_id', '=', self.company.id)])
        if not self.steps:
            self.steps = Step.create([
                {'name': 'Greet and note the visit', 'step_type': 'note', 'sequence': 10},
                {'name': 'Photo of the shelf', 'step_type': 'photo', 'sequence': 20},
                {'name': 'Stock count', 'step_type': 'stock', 'sequence': 30},
                {'name': 'Shelf audit form', 'step_type': 'form', 'form_id': self.shelf_form.id, 'sequence': 40},
                {'name': 'Take demand', 'step_type': 'order', 'sequence': 50},
                {'name': 'Collect payment', 'step_type': 'payment', 'sequence': 60, 'mandatory': False},
            ])

    # ------------------------------------------------------------------
    @staticmethod
    def _utc(day, hour, minute=0):
        local = pytz.timezone(TZ).localize(datetime.combine(day, time(hour, minute)))
        return local.astimezone(pytz.utc).replace(tzinfo=None)

    def _history(self):
        env = self.env
        modes = env['ff.collection.mode'].search([])
        cash = modes.filtered(lambda m: m.mode_type == 'cash')[:1] or modes[:1]
        online = modes.filtered(lambda m: m.mode_type == 'online')[:1] or cash
        cheque = modes.filtered(lambda m: m.mode_type == 'cheque')[:1] or cash
        expense_types = env['ff.expense.category'].search([])
        outcomes = env['ff.visit.outcome'].search([])
        order_outcome = outcomes.filtered('is_order')[:1] or outcomes[:1]
        self.visits = env['ff.visit']
        counter = 0
        reps = [k for k in self.people if self.level[k] == 4]
        for back in range(DAYS - 1, -1, -1):
            day = self.today - timedelta(days=back)
            if day.weekday() == 6:
                continue
            for key, employee in self.people.items():
                if (back == 2 and key in ('rep04', 'rep11')) or (back == 4 and key == 'rep17'):
                    continue  # a few absences for the calendar and reports
                centre = self.centre(key)
                late = key in ('rep02', 'rep09', 'rep15') and back in (1, 5)
                check_in = self._utc(day, 9 if not late else 10, random.choice([10, 20, 25, 30]))
                env['hr.attendance'].create({
                    'employee_id': employee.id, 'check_in': check_in,
                    'check_out': False if back == 0 else self._utc(day, 18, random.choice([30, 40, 50])),
                    'in_latitude': centre[0], 'in_longitude': centre[1],
                    'out_latitude': centre[0] + 0.004, 'out_longitude': centre[1] + 0.004,
                    'ff_source': 'app', 'ff_shift_id': self.shift.id if self.shift else False,
                    'ff_in_address': '%s office' % next(a[2] for a in AREAS if a[3] == centre)
                    if any(a[3] == centre for a in AREAS) else 'Regional office',
                    'ff_out_address': 'Last customer of the day', 'ff_in_accuracy': 12, 'ff_out_accuracy': 15,
                })

            for rep_key in reps:
                if (back == 2 and rep_key in ('rep04', 'rep11')) or (back == 4 and rep_key == 'rep17'):
                    continue
                rep = self.people[rep_key]
                area = self.area_of[rep_key]
                beats = self.beats.get(area) or env['ff.beat']
                if not beats:
                    continue
                beat = beats[(back + int(rep_key[3:])) % len(beats)]
                plan = env['ff.beat.plan'].create({
                    'employee_id': rep.id, 'beat_id': beat.id, 'date': day,
                    'customer_line_ids': [(0, 0, {'partner_id': line.partner_id.id, 'sequence': line.sequence})
                                          for line in beat.line_ids],
                })
                hour = 10
                path = [self.centre(rep_key)]
                for line in plan.customer_line_ids:
                    partner = line.partner_id
                    if back == 0 and hour > 12:
                        break
                    if random.random() < 0.18:
                        continue
                    counter += 1
                    offsite = counter % 11 == 0
                    arrive = self._utc(day, hour, random.randint(0, 25))
                    leave = arrive + timedelta(minutes=random.randint(10, 32))
                    open_visit = back == 0 and hour == 12
                    visit = env['ff.visit'].create({
                        'employee_id': rep.id, 'partner_id': partner.id, 'check_in_at': arrive,
                        'check_out_at': False if open_visit else leave, 'state': 'ongoing' if open_visit else 'done',
                        'check_in_lat': partner.partner_latitude + (0.015 if offsite else 0.0002),
                        'check_in_lng': partner.partner_longitude, 'distance_m': 1650 if offsite else 28,
                        'inside_geofence': not offsite, 'visit_type': 'offsite' if offsite else 'onsite',
                        'offsite_reason': 'Owner met near the bus stand' if offsite else False,
                        'outcome_id': (order_outcome if counter % 4 else outcomes[counter % len(outcomes)]).id
                        if outcomes else False,
                        'beat_plan_id': plan.id,
                    })
                    self.visits |= visit
                    line.visit_id = visit.id
                    path.append((partner.partner_latitude, partner.partner_longitude))
                    hour += 1
                    if open_visit:
                        continue
                    self._visit_details(visit, rep, partner, arrive, counter, back)
                    if random.random() < 0.8:
                        chosen = random.sample(list(self.products), random.randint(2, 5))
                        demand = env['ff.demand'].create({
                            'employee_id': rep.id, 'partner_id': partner.id, 'visit_id': visit.id,
                            'distributor_id': partner.ff_distributor_id.id, 'route_id': beat.id,
                            'date': arrive + timedelta(minutes=9), 'note': 'Weekly replenishment',
                            'line_ids': [(0, 0, {'product_id': p.id, 'quantity': random.choice([6, 12, 18, 24, 36]),
                                                 'price_unit': p.ff_ptr}) for p in chosen],
                        })
                        if back >= 5:
                            demand.state = 'supplied'
                        elif back >= 3:
                            demand.state = 'quoted'
                            for demand_line in demand.line_ids:
                                demand_line.quoted_quantity = demand_line.quantity
                        elif back == 2 and counter % 2:
                            demand.state = 'partial'
                            for demand_line in demand.line_ids[:1]:
                                demand_line.quoted_quantity = demand_line.quantity / 2
                    if random.random() < 0.45:
                        mode = random.choice([cash, cash, online, cheque])
                        env['ff.collection'].create({
                            'employee_id': rep.id, 'partner_id': partner.id, 'visit_id': visit.id, 'mode_id': mode.id,
                            'amount': random.choice([1200, 2500, 3600, 4800, 6400, 9100]),
                            'date': arrive + timedelta(minutes=16),
                            'reference': ('UPI%09d' % counter) if mode == online else
                                         ('CHQ%06d' % counter) if mode == cheque else False,
                            'state': 'collected' if mode.needs_deposit else 'received',
                            'latitude': partner.partner_latitude, 'longitude': partner.partner_longitude,
                        })
                self._pings(rep, day, path, back)
                if expense_types and back in (1, 3, 5):
                    claim = env['ff.expense.claim'].create({
                        'employee_id': rep.id, 'date': day, 'category_id': expense_types[back % len(expense_types)].id,
                        'amount': random.choice([150, 220, 300, 450]),
                        'note': random.choice(['Parking near market', 'Team tea with retailers', 'Bus fare',
                                               'Samples courier']),
                    })
                    if back >= 3 and hasattr(claim, 'action_submit'):
                        try:
                            with env.cr.savepoint():
                                claim.action_submit()
                        except Exception:  # noqa: BLE001
                            pass
                env['ff.daily.track'].create({
                    'employee_id': rep.id, 'date': day, 'distance_km': round(random.uniform(22, 58), 1),
                    'ping_count': random.randint(140, 280), 'first_ping_at': self._utc(day, 9, 20),
                    'last_ping_at': self._utc(day, 13 if back == 0 else 18, 30),
                })

    def _visit_details(self, visit, rep, partner, arrive, counter, back):
        """Steps, a stock count and the shelf form on most visits."""
        env = self.env
        if counter % 3 == 0 and 'ff.stock.count' in env:
            count = env['ff.stock.count'].create({
                'partner_id': partner.id, 'employee_id': rep.id, 'visit_id': visit.id,
                'date': arrive + timedelta(minutes=4), 'note': 'Counted on the shelf and store room',
                'line_ids': [(0, 0, {'product_id': p.id, 'quantity': random.randint(0, 30)})
                             for p in self.products[:5]],
            })
        else:
            count = env['ff.stock.count'] if 'ff.stock.count' in env else None
        if counter % 2 == 0 and getattr(self, 'shelf_form', None):
            share = random.randint(15, 60)
            answers = {'shelf_share': share, 'competitor_offer': counter % 4 == 0,
                       'display': random.choice(['Good', 'Average', 'Poor']), 'rating': random.randint(3, 5),
                       'remarks': 'Needs more facings for shampoo' if share < 30 else 'Good placement'}
            response = env['ff.form.response'].create({
                'form_id': self.shelf_form.id, 'employee_id': rep.id, 'partner_id': partner.id, 'visit_id': visit.id,
                'submitted_at': arrive + timedelta(minutes=6), 'answers': answers,
                'latitude': partner.partner_latitude, 'longitude': partner.partner_longitude,
                'line_ids': [(0, 0, {'field_id': field.id, 'field_label': field.name,
                                     'value_text': str(answers.get(field.key, '')),
                                     'value_number': float(answers[field.key]) if isinstance(answers.get(field.key), int)
                                     and not isinstance(answers.get(field.key), bool) else 0.0})
                             for field in self.shelf_form.field_ids],
            })
            _ = response
        for step in getattr(self, 'steps', env['ff.visit.step']):
            skipped = step.step_type == 'payment' and counter % 2
            env['ff.visit.step.record'].create({
                'visit_id': visit.id, 'step_id': step.id, 'state': 'skipped' if skipped else 'done',
                'note': 'Owner available, shelf checked' if step.step_type == 'note' else False,
                'skip_reason': 'No payment due today' if skipped else False,
                'stock_count_id': count.id if count and step.step_type == 'stock' else False,
                'done_at': arrive + timedelta(minutes=2 + step.sequence // 10),
            })

    def _pings(self, rep, day, path, back):
        """A GPS trail between the stops, so the timeline and live map have a route."""
        Ping = self.env['ff.location.ping']
        end_hour = 13 if back == 0 else 18
        if back > 2:
            return  # recent days only, to keep the demo light
        points = []
        for (a_lat, a_lng), (b_lat, b_lng) in zip(path, path[1:] + path[-1:]):
            for step in range(4):
                t = step / 4.0
                points.append((a_lat + (b_lat - a_lat) * t, a_lng + (b_lng - a_lng) * t))
        start = self._utc(day, 9, 30)
        span = (self._utc(day, end_hour, 0) - start).total_seconds()
        for index, (lat, lng) in enumerate(points):
            Ping.create({
                'employee_id': rep.id, 'ts': start + timedelta(seconds=span * index / max(len(points), 1)),
                'latitude': lat + random.uniform(-0.0004, 0.0004), 'longitude': lng + random.uniform(-0.0004, 0.0004),
                'accuracy': random.choice([8, 12, 18, 25]), 'speed': random.uniform(0, 9),
                'battery': max(15, 95 - index * 2), 'gps_on': True, 'source': 'background',
                'client_uuid': str(uuid.uuid4()),
            })

    # ------------------------------------------------------------------
    def _route_plans(self):
        env = self.env
        month = self.today.replace(day=1)
        for key in [k for k in self.people if self.level[k] == 4][:10]:
            employee = self.people[key]
            plan = env['ff.route.plan'].create({'employee_id': employee.id, 'month': month,
                                                'note': 'Monthly beat plan (demo)'})
            env['ff.beat.plan'].search([('employee_id', '=', employee.id), ('date', '>=', month)]).write(
                {'plan_id': plan.id})
            beats = self.beats.get(self.area_of[key])
            for offset in range(1, 6):
                day = self.today + timedelta(days=offset)
                if day.weekday() == 6 or not beats:
                    continue
                beat = beats[offset % len(beats)]
                env['ff.beat.plan'].create({
                    'plan_id': plan.id, 'employee_id': employee.id, 'beat_id': beat.id, 'date': day,
                    'customer_line_ids': [(0, 0, {'partner_id': line.partner_id.id, 'sequence': line.sequence})
                                          for line in beat.line_ids],
                })
            plan.state = 'confirmed'

    def _route_distances(self):
        for area, beats in self.beats.items():
            if len(beats) >= 2:
                self.env['ff.route.distance'].create({'from_beat_id': beats[0].id, 'to_beat_id': beats[1].id,
                                                      'distance_km': round(random.uniform(6, 18), 1)})

    def _returns(self):
        env = self.env
        reasons = ['damaged', 'expired', 'near_expiry', 'wrong_item', 'unsold']
        states = ['submitted', 'approved', 'rejected', 'submitted', 'approved']
        for index, visit in enumerate(self.visits.filtered(lambda v: v.state == 'done')[:12]):
            env['ff.return'].create({
                'employee_id': visit.employee_id.id, 'partner_id': visit.partner_id.id, 'visit_id': visit.id,
                'date': visit.check_in_at + timedelta(minutes=12), 'reason': reasons[index % len(reasons)],
                'state': states[index % len(states)], 'note': 'Found during the shelf check',
                'latitude': visit.partner_id.partner_latitude, 'longitude': visit.partner_id.partner_longitude,
                'line_ids': [(0, 0, {'product_id': p.id, 'quantity': random.randint(1, 6), 'price_unit': p.ff_ptr,
                                     'batch': 'B%04d' % (index * 37 + 11),
                                     'expiry_date': self.today + timedelta(days=15 - index * 4)})
                             for p in self.products[index % 5:(index % 5) + 2]],
            })

    def _deposits(self):
        env = self.env
        for key in [k for k in self.people if self.level[k] == 4][::3]:
            employee = self.people[key]
            held = env['ff.collection'].search([('employee_id', '=', employee.id), ('state', '=', 'collected'),
                                                ('date', '<', self._utc(self.today - timedelta(days=2), 0))])
            if not held:
                continue
            deposit = env['ff.collection.deposit'].create({
                'employee_id': employee.id, 'reference': 'SLIP-%s' % key.upper(),
                'note': 'Deposited at the branch', 'submitted_at': fields.Datetime.now() - timedelta(days=1),
            })
            held.write({'deposit_id': deposit.id, 'state': 'submitted'})
            if key in ('rep01', 'rep07', 'rep13'):
                deposit.write({'state': 'received', 'received_at': fields.Datetime.now(),
                               'received_by_id': env.ref('base.user_admin').id})
                held.write({'state': 'received'})

    def _allowance_claims(self):
        env = self.env
        states = ['approved', 'submitted', 'draft', 'rejected']
        for index, key in enumerate([k for k in self.people if self.level[k] == 4]):
            employee = self.people[key]
            for back in (1, 2):
                day = self.today - timedelta(days=back)
                km = round(random.uniform(24, 55), 1)
                env['ff.allowance.claim'].create({
                    'employee_id': employee.id, 'date': day, 'policy_id': self.policy.id if self.policy else False,
                    'basis': 'gps', 'distance_km': km, 'rate_per_km': 3.5, 'amount': round(km * 3.5, 2),
                    'visit_count': random.randint(3, 6), 'state': states[(index + back) % len(states)],
                    'note': 'Daily travel allowance',
                    'line_ids': [(0, 0, {'sequence': 1, 'name': 'Office to first outlet', 'distance_km': round(km / 3, 1)}),
                                 (0, 0, {'sequence': 2, 'name': 'Outlet to outlet', 'distance_km': round(km / 3, 1)}),
                                 (0, 0, {'sequence': 3, 'name': 'Last outlet to home', 'distance_km': round(km / 3, 1)})],
                })

    def _regularisations(self):
        env = self.env
        cases = [('rep04', 2, 'battery', 'submitted'), ('rep11', 2, 'network', 'approved'),
                 ('rep17', 4, 'field_duty', 'submitted'), ('rep06', 3, 'forgot', 'rejected')]
        for key, back, reason, state in cases:
            day = self.today - timedelta(days=back)
            env['ff.regularisation'].create({
                'employee_id': self.people[key].id, 'date': day, 'check_in': self._utc(day, 9, 30),
                'check_out': self._utc(day, 18, 30), 'reason': reason, 'state': state,
                'note': 'Worked the full route; the punch did not go through.',
            })

    def _leaves(self):
        env = self.env
        LeaveType = env['hr.leave.type']
        leave_type = LeaveType.search([('name', '=', 'Casual Leave (Demo)')], limit=1)
        if not leave_type:
            values = {'name': 'Casual Leave (Demo)', 'company_id': self.company.id}
            if 'requires_allocation' in LeaveType._fields:
                field = LeaveType._fields['requires_allocation']
                values['requires_allocation'] = False if field.type == 'boolean' else 'no'
            leave_type = LeaveType.create(values)
        Leave = env['hr.leave'].with_context(leave_skip_state_check=True, mail_create_nolog=True)
        cases = [('rep03', 0, 1, 'validate'), ('rep08', 1, 2, 'confirm'), ('rep14', 3, 3, 'validate'),
                 ('rep19', -4, -3, 'confirm'), ('chn', -6, -6, 'confirm'), ('rep12', 5, 5, 'refuse')]
        for key, start_back, end_back, state in cases:
            start = self.today - timedelta(days=start_back)
            end = self.today - timedelta(days=end_back) if end_back <= start_back else start
            if end < start:
                start, end = end, start
            try:
                with env.cr.savepoint():
                    leave = Leave.create({
                        'employee_id': self.people[key].id, 'holiday_status_id': leave_type.id,
                        'request_date_from': start, 'request_date_to': end,
                        'name': 'Family function' if state != 'refuse' else 'Personal work',
                    })
                    if state != 'confirm':
                        leave.sudo().write({'state': state})
            except Exception:  # noqa: BLE001 - leave rules differ per database
                _logger.info('South demo: leave for %s skipped', key)

    def _targets(self):
        env = self.env
        Target = env['ff.target']
        month = self.today.replace(day=1)
        rule = env['ff.incentive.rule'].create({
            'name': 'South monthly incentive (Demo)', 'condition': 'pro_rata', 'threshold_pct': 60, 'cap_pct': 125,
            'visit_amount': 1500, 'sales_amount': 4000, 'collection_amount': 2500,
        })
        top = Target.create({'scope': 'team', 'team_id': self.teams['head'].id, 'month': month,
                             'visit_target': 1800, 'customer_target': 60, 'sales_target': 3600000,
                             'collection_target': 1200000, 'incentive_rule_id': rule.id})
        weights = {'tn': 0.4, 'kl': 0.3, 'ka': 0.3}
        top.ff_split(self.people['head'], [
            {'scope': 'team', 'id': self.teams[k].id, 'visits': int(1800 * w), 'customers': int(60 * w),
             'sales': int(3600000 * w), 'collections': int(1200000 * w)} for k, w in weights.items()])
        for state_key in STATES:
            parent = top.child_ids.filtered(lambda t, k=state_key: t.team_id == self.teams[k])
            areas = [a[0] for a in AREAS if a[1] == state_key]
            parent.ff_split(self.people[state_key], [
                {'scope': 'team', 'id': self.teams[a].id, 'visits': parent.visit_target // len(areas),
                 'customers': parent.customer_target // len(areas), 'sales': parent.sales_target // len(areas),
                 'collections': parent.collection_target // len(areas)} for a in areas])
            for area in areas:
                area_target = parent.child_ids.filtered(lambda t, a=area: t.team_id == self.teams[a])
                reps = [k for k in self.people if self.area_of.get(k) == area and self.level[k] == 4]
                if not area_target or not reps:
                    continue
                area_target.ff_split(self.people[area], [
                    {'scope': 'employee', 'id': self.people[r].id, 'visits': area_target.visit_target // len(reps),
                     'customers': area_target.customer_target // len(reps),
                     'sales': area_target.sales_target // len(reps),
                     'collections': area_target.collection_target // len(reps)} for r in reps])

    def _tasks(self):
        env = self.env
        names = ['Put up the festival offer poster', 'Collect the pending cheque', 'Check coffee stock after promo',
                 'Introduce biscuits to the new outlet', 'Photo of competitor display', 'Update the shop GST number']
        states = ['todo', 'in_progress', 'done', 'todo']
        Task = env['ff.task']
        state_field = 'state' in Task._fields
        for index, key in enumerate([k for k in self.people if self.level[k] == 4]):
            employee = self.people[key]
            values = {
                'name': names[index % len(names)], 'employee_id': employee.id,
                'date_deadline': self.today + timedelta(days=(index % 5) - 1), 'priority': str(index % 3),
                'requires_photo': index % 4 == 0, 'assigned_by_employee_id': employee.parent_id.id,
            }
            task = Task.create({k: v for k, v in values.items() if k in Task._fields})
            if state_field:
                try:
                    with env.cr.savepoint():
                        task.state = states[index % len(states)]
                except Exception:  # noqa: BLE001
                    pass

    def _alerts(self):
        env = self.env
        kinds = ['inactive', 'no_signal', 'gps_off', 'offsite_visit', 'mock_location', 'app_killed']
        for index, key in enumerate(['rep02', 'rep05', 'rep09', 'rep12', 'rep16', 'rep20']):
            employee = self.people[key]
            env['ff.alert'].create({
                'employee_id': employee.id, 'manager_id': employee.parent_id.id, 'kind': kinds[index],
                'message': '%s: %s' % (employee.name, dict(env['ff.alert']._fields['kind'].selection)[kinds[index]]),
                'seen': index % 2 == 0,
            })

    def _notifications(self):
        env = self.env
        for key, employee in self.people.items():
            if self.level[key] == 4:
                env['ff.notification'].create({
                    'employee_id': employee.id, 'title': 'Target for this month is set',
                    'body': 'Open Leaderboard & targets to see your split.', 'kind': 'info'})
            else:
                env['ff.notification'].create({
                    'employee_id': employee.id, 'user_id': employee.user_id.id or False,
                    'title': 'Expense claims waiting', 'body': 'Your team has claims to approve.', 'kind': 'approval'})

    def _compliance(self):
        env = self.env
        events = [('rep02', 'gps_off'), ('rep02', 'gps_on'), ('rep09', 'battery_saver_on'),
                  ('rep12', 'permission_revoked'), ('rep12', 'permission_granted'), ('rep16', 'mock_location'),
                  ('rep20', 'app_killed'), ('rep05', 'time_tampered')]
        for index, (key, event) in enumerate(events):
            env['ff.compliance.log'].create({
                'employee_id': self.people[key].id, 'event': event,
                'ts': fields.Datetime.now() - timedelta(hours=index + 1), 'detail': 'Reported by the app (demo)',
                'client_uuid': str(uuid.uuid4()),
            })

    def _live_status(self):
        env = self.env
        now = fields.Datetime.now()
        for index, (key, employee) in enumerate(self.people.items()):
            if key in ('rep03', 'rep14'):
                continue  # on leave today
            lat, lng = self.centre(key)
            angle = index * 1.3
            lat, lng = lat + 0.02 * math.sin(angle), lng + 0.02 * math.cos(angle)
            idle = key in ('rep05', 'rep16')
            no_signal = key == 'rep20'
            env['ff.employee.status']._ff_get(employee).write({
                'punched_in': key not in ('rep06',), 'punched_in_at': self._utc(self.today, 9, 20 + index % 25),
                'last_ping_at': now - timedelta(minutes=45 if no_signal else 2 + index % 6),
                'latitude': lat, 'longitude': lng, 'accuracy': 10 + index % 20,
                'battery': [88, 64, 41, 17, 93, 72][index % 6], 'gps_on': key != 'rep02',
                'is_charging': index % 7 == 0,
                'moved_at': now - timedelta(minutes=50 if idle else 3),
            })
