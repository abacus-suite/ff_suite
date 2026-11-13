import json
import logging
import urllib.request
try:
    import requests
except ImportError:
    requests = None

from odoo import api, fields, models
from odoo.exceptions import AccessError, ValidationError
from odoo.tools.safe_eval import safe_eval

from odoo.addons.ff_base.tools import get_param, map_link

_logger = logging.getLogger(__name__)

APPROVAL_STATES = [
    ('approved', 'Approved'),
    ('pending', 'Pending Approval'),
    ('rejected', 'Rejected'),
]


class ResPartner(models.Model):
    _inherit = 'res.partner'

    postal_district = fields.Char(string='Postal District', index=True)
    postal_city = fields.Char(string='Postal City / Taluk', index=True)
    postal_area = fields.Char(string='Postal Area / Locality', index=True)

    ff_is_client = fields.Boolean(string='Field Contact', index=True,
                                  help='Visible to field staff in the mobile app.')
    ff_category_id = fields.Many2one('ff.contact.category', string='Contact Category', index=True, tracking=True)
    ff_category_type = fields.Selection(related='ff_category_id.category_type', store=True, string='Contact Type')
    ff_is_distributor = fields.Boolean(string='Distributor', index=True,
                                        help='Tick if this contact is a distributor/dealer that supplies outlets.')
    ff_employee_ids = fields.Many2many('hr.employee', 'ff_partner_employee_rel', 'partner_id', 'employee_id',
                                       string='Field Employees',
                                       help='Employees who work with this contact. Only they (and their managers) see it in the app.')
    ff_district_id = fields.Many2one('ff.district', string='District / Territory', index=True)
    ff_secondary_district_ids = fields.Many2many(
        'ff.district', 'ff_partner_secondary_district_rel', 'partner_id', 'district_id',
        string='Secondary Districts / Territories',
        help='Additional cities covered by this distributor.')
    ff_district_ids = fields.Many2many(
        'ff.district', compute='_compute_ff_district_ids', string='All Districts / Territories')
    ff_client_code = fields.Char(string='Client Code', index=True, copy=False)
    ff_team_ids = fields.Many2many('ff.team', string='Regions', help='Informational grouping of the contact.')
    ff_geofence_radius = fields.Integer(string='Geofence Radius (m)',
                                        help='0 = use the default radius from Field Force settings.')
    ff_approval_state = fields.Selection(APPROVAL_STATES, string='Contact Approval',
                                         default='approved', index=True, copy=False)
    ff_created_by_employee_id = fields.Many2one('hr.employee', string='Added by (Field)',
                                                readonly=True, copy=False)
    ff_map_url = fields.Char(string='Map', compute='_compute_ff_map_url')

    @api.depends('ff_district_id', 'ff_secondary_district_ids')
    def _compute_ff_district_ids(self):
        for partner in self:
            partner.ff_district_ids = partner.ff_district_id | partner.ff_secondary_district_ids

    @api.onchange('ff_district_id')
    def _onchange_ff_district_id(self):
        district = self.ff_district_id
        if district:
            self.state_id = district.state_id
            self.country_id = district.country_id
            if not self.city:
                self.city = district.name

    def _compute_ff_map_url(self):
        for partner in self:
            partner.ff_map_url = partner._ff_has_location() and map_link(
                partner.env, partner.partner_latitude, partner.partner_longitude) or False

    def _ff_has_location(self):
        self.ensure_one()
        return bool(self.partner_latitude or self.partner_longitude)

    def _ff_radius(self):
        self.ensure_one()
        return self.ff_geofence_radius or get_param(self.env, 'geofence_radius')

    @api.model
    def _ff_beat_required(self):
        """Must an outlet or a distributor sit on a beat?

        This is checked where a person chooses the type - the app, and the
        contact form - rather than on every write: a contact is often created
        first and put on its beat a moment later, and a rule that fires in
        between would stop imports and demo data dead.
        """
        return self.env['ir.config_parameter'].sudo().get_param('ff_base.beat_required', 'True') != 'False'

    @api.model
    def _ff_check_beat(self, category, routes):
        """Raise when this kind of contact needs a beat and none was given."""
        kind = category.category_type if category else False
        if kind in ('outlet', 'distributor') and self._ff_beat_required() and not routes:
            raise ValidationError(self.env._(
                'An %(kind)s needs a beat. Choose one, or add it as a lead for now.',
                kind=dict(self.env['ff.contact.category']._fields['category_type'].selection).get(kind, kind)))

    @api.model
    def _ff_ownership_domain(self, employee):
        """Which contacts "belong" to an employee. Other modules widen this."""
        return [('ff_employee_ids', 'in', employee._ff_scope_employees().ids)]

    @api.model
    def _ff_contact_access(self):
        """'scoped' keeps contacts with their owner; 'open' shares the beats."""
        forced = self.env.context.get('ff_force_access')
        if forced in ('scoped', 'open'):
            return forced
        access = self.env['ir.config_parameter'].sudo().get_param('ff_base.contact_access')
        return access if access in ('scoped', 'open') else 'scoped'

    @api.model
    def _ff_access_rule(self, employee):
        """The contact-list rule that applies to ``employee``; none here (see ff_contact_access)."""
        return False

    @api.model
    def _ff_see_all(self):
        """Does everybody see every contact? On unless ``ff_base.contact_see_all`` is set to False.

        Until the employees are set on the contacts, ownership would hide most of them (leads above all),
        so for now nobody is held back by who the contact belongs to or who added it.
        """
        if self.env.context.get('ff_all_contacts'):
            return True
        if self.env.context.get('ff_force_access'):
            return False  # a rule asked for the scoped or open way of the base list
        value = self.env['ir.config_parameter'].sudo().get_param('ff_base.contact_see_all')
        return value not in ('False', 'false', '0')

    @api.model
    def _ff_allocation_domain(self, employee):
        """The extra limit of "Allocated Outlets" / "Allocated Distributors" on the employee.

        With a switch on, that kind of contact (outlets, or distributors) is only theirs when their name is on it
        (Field Employees). Everything else, and a person with both switches off, follows the usual rule. A
        lead is never touched here.
        """
        from odoo.fields import Domain
        employee = employee.sudo()
        outlets_only = employee.ff_allocated_outlets
        distributors_only = employee.ff_allocated_distributors
        if not (outlets_only or distributors_only):
            return []
        distributor = ['|', ('ff_category_type', '=', 'distributor'), ('ff_is_distributor', '=', True)]
        outlet = ['|', ('ff_category_type', '=', False), ('ff_category_type', 'not in', ('distributor', 'lead')),
                  ('ff_is_distributor', '!=', True)]
        if 'is_distributor' in self._fields:
            distributor = ['|'] + distributor + [('is_distributor', '=', True)]
            outlet.append(('is_distributor', '!=', True))
        lead = [('ff_category_type', '=', 'lead')]
        mine = [('ff_employee_ids', 'in', [employee.id])]
        parts = []
        if outlets_only:
            # Anything that is not an outlet stays as it was; an outlet only when it is theirs.
            parts.append(Domain.OR([Domain(distributor), Domain(lead), Domain(mine)]))
        if distributors_only:
            parts.append(Domain.OR([Domain(outlet), Domain(lead), Domain(mine)]))
        return list(Domain.AND(parts))

    @api.model
    def _ff_visible_domain(self, employee):
        """Contacts an employee may see in the app.

        Scoped: their own and those of people in their data access.
        Open: every contact that sits on a beat, so a shared territory works
        and the same outlet can be called on by more than one person.
        A lead is private either way - only whoever added it and the managers
        above them see it, until it becomes a real customer with a beat.
        """
        employee = employee.sudo()
        if self._ff_see_all():
            return [
                ('ff_is_client', '=', True),
                ('company_id', 'in', (False, employee.company_id.id)),
                '|', ('ff_category_id', '=', False), ('ff_category_id.show_in_app', '=', True),
                '|', '|', ('ff_approval_state', '=', 'approved'), ('ff_approval_state', '=', False),
                '&', ('ff_approval_state', '=', 'pending'), ('ff_created_by_employee_id', '=', employee.id),
            ]
        categories = self.env['ff.contact.category'].ff_for_employee(employee)
        # A contact that has never been through approval has no state at all -
        # everything brought across from an older system is like that - and it
        # is not pending anybody's decision, so it counts as settled.
        approval = [
            '|', '|', ('ff_approval_state', '=', 'approved'), ('ff_approval_state', '=', False),
            '&', ('ff_approval_state', '=', 'pending'), ('ff_created_by_employee_id', '=', employee.id),
        ]
        if self._ff_contact_access() != 'open':
            return [
                ('ff_is_client', '=', True),
                # Uncategorised contacts are shown too: an import arrives before
                # anybody has said what each one is, and hiding them would hide
                # the very list somebody has to work through to say so.
                '|', ('ff_category_id', 'in', categories.ids), ('ff_category_id', '=', False),
            '|', ('ff_category_id', '=', False), ('ff_category_id.show_in_app', '=', True),
            ] + self._ff_ownership_domain(employee) + approval

        # Open access: every contact the company works with, whether or not a
        # beat has been set on it yet, plus this person's own leads. A lead
        # stays with whoever added it and the managers above them.
        mine = (employee | employee._ff_subordinates()).ids
        return [
            ('ff_is_client', '=', True),
            ('company_id', 'in', (False, employee.company_id.id)),
            '|',
            ('ff_category_type', '!=', 'lead'),
            '|', ('ff_created_by_employee_id', 'in', mine), ('ff_employee_ids', 'in', mine),
            '|', ('ff_category_id', '=', False), ('ff_category_id.show_in_app', '=', True),
        ] + approval

    @api.model
    def ff_action_open_clients(self):
        """Contacts menu: each user sees their department's categories and the
        contacts assigned within their data access."""
        action = self.env['ir.actions.act_window']._for_xml_id('ff_clients.ff_client_action')
        user = self.env.user
        employee = user.employee_id
        if employee:
            action['context'] = dict(safe_eval(action.get('context') or '{}'),
                                     default_ff_employee_ids=[(6, 0, employee.ids)])
        if not user.has_group('ff_base.group_ff_admin'):
            categories = self.env['ff.contact.category'].with_context(ff_all_categories=True).ff_for_employee(employee)
            action['domain'] = [('ff_is_client', '=', True), ('ff_category_id', 'in', categories.ids),
                                ('ff_employee_ids', 'in', user.ff_scope_employee_ids())]
        return action

    @api.model
    def ff_create_from_app(self, employee, vals):
        employee = employee.sudo()
        vals = dict(vals)
        extra_employee_ids = vals.pop('ff_extra_employee_ids', None) or []
        category = self.env['ff.contact.category'].sudo().browse(vals.get('ff_category_id')).exists()
        if not category or category not in self.env['ff.contact.category'].ff_for_employee(employee):
            raise ValidationError(self.env._('Choose a contact category you have access to.'))
        # Supervisors, and categories without approval, are approved immediately.
        auto_approve = employee.ff_access_scope != 'own' or not category.requires_approval
        vals.update(
            ff_is_client=True,
            ff_approval_state='approved' if auto_approve else 'pending',
            ff_created_by_employee_id=employee.id,
            ff_employee_ids=[(6, 0, list({employee.id, *extra_employee_ids}))],
        )
        district = self.env['ff.district'].sudo().browse(vals.get('ff_district_id')).exists()
        if district:
            vals.setdefault('state_id', district.state_id.id)
            vals.setdefault('country_id', district.country_id.id)
            vals['city'] = vals.get('city') or district.name
        if not vals.get('parent_id'):
            vals.setdefault('is_company', True)
        partner = self.sudo().create(vals)
        manager_user = employee.parent_id.user_id
        if not auto_approve and manager_user:
            try:
                partner.activity_schedule('mail.mail_activity_data_todo', user_id=manager_user.id,
                                          summary=self.env._('Approve new field contact'))
            except Exception:
                pass
        if not auto_approve and employee.parent_id and 'ff.notification' in self.env:
            self.env['ff.notification'].sudo().ff_push(
                title=self.env._('New Outlet to Approve'),
                body=self.env._('%(who)s onboarded %(outlet)s.', who=employee.name, outlet=partner.name),
                kind='approval',
                employee=employee.parent_id,
                record=partner,
            )
        return partner

    def _ff_can_be_decided_by(self, approver):
        self.ensure_one()
        creator = self.ff_created_by_employee_id
        if not approver:
            return False
        if creator:
            return approver._ff_is_manager_of(creator)
        return approver.sudo().ff_access_scope != 'own'

    def _ff_check_can_approve(self):
        user = self.env.user
        if user.has_group('ff_base.group_ff_admin'):
            return
        for partner in self:
            if not user.has_group('ff_base.group_ff_manager') or not partner._ff_can_be_decided_by(user.employee_id):
                raise AccessError(self.env._('This contact is outside your data access.'))

    def _ff_decide(self, approve):
        self.sudo().write({'ff_approval_state': 'approved' if approve else 'rejected'})
        self.sudo().activity_ids.unlink()
        if 'ff.notification' in self.env:
            for partner in self:
                who = partner.ff_created_by_employee_id
                if who:
                    self.env['ff.notification'].sudo().ff_push(
                        title=self.env._('Client Approved') if approve else self.env._('Client Rejected'),
                        body=self.env._('Contact %(name)s was %(status)s.',
                                        name=partner.name,
                                        status=self.env._('approved') if approve else self.env._('rejected')),
                        kind='decision',
                        employee=who,
                        record=partner,
                    )

    def action_ff_approve(self):
        self._ff_check_can_approve()
        self._ff_decide(True)

    def action_ff_reject(self):
        self._ff_check_can_approve()
        self._ff_decide(False)

    def ff_app_decide(self, employee, approve):
        """Approve or reject from the mobile app on behalf of ``employee``."""
        self.ensure_one()
        if self.ff_approval_state != 'pending' or not self._ff_can_be_decided_by(employee):
            raise AccessError(self.env._('This contact is outside your data access.'))
        self._ff_decide(approve)

    # -------------------------------------------------------------------------
    # Postal API & Locality Cron (Option B: Smart match or first unique)
    # -------------------------------------------------------------------------
    @api.model
    def _fetch_postal_info(self, pincode):
        """Call postal API and return district, taluk/block, and unique localities."""
        url = f"https://api.postalpincode.in/pincode/{pincode}"
        data = None
        try:
            if requests:
                resp = requests.get(url, timeout=10, headers={'User-Agent': 'Mozilla/5.0'})
                if resp.status_code == 200:
                    data = resp.json()
            else:
                req = urllib.request.Request(url, headers={'User-Agent': 'Mozilla/5.0'})
                with urllib.request.urlopen(req, timeout=10) as r:
                    data = json.loads(r.read().decode('utf-8'))
        except Exception as e:
            _logger.warning("Failed to fetch postal info for PIN %s: %s", pincode, e)
            return None

        if not data or not isinstance(data, list) or not data[0].get("Status") == "Success":
            return None

        post_offices = data[0].get("PostOffice") or []
        if not post_offices:
            return None

        district = None
        taluk = None
        localities = []
        seen_localities = set()

        for office in post_offices:
            if not district and office.get("District"):
                district = office["District"].strip()
            if not taluk and office.get("Block") and office["Block"].strip().upper() not in ('NA', ''):
                taluk = office["Block"].strip()
            name = (office.get("Name") or '').strip()
            if name and name.upper() not in seen_localities:
                seen_localities.add(name.upper())
                localities.append(name)

        if not taluk:
            for office in post_offices:
                div = (office.get("Division") or '').strip()
                if div and div.upper() not in ('NA', ''):
                    taluk = div
                    break

        return {
            'district': district,
            'taluk': taluk,
            'localities': localities,
        }

    @api.model
    def _match_postal_locality(self, partner, localities):
        """Option B: Smart match with contact address / name, or first unique locality."""
        if not localities:
            return False
        if len(localities) == 1:
            return localities[0]

        search_text = " ".join([
            partner.name or '',
            partner.street or '',
            partner.street2 or '',
            partner.city or '',
        ]).upper()

        for loc in localities:
            if loc.upper() in search_text:
                return loc

        return localities[0]

    @api.model
    def cron_fetch_postal_data(self, batch_size=200):
        """Fetch district, city/taluk, and area/locality from postal API for contacts with zip."""
        domain = [
            ('zip', '!=', False),
            '|', '|',
            ('postal_area', '=', False),
            ('postal_city', '=', False),
            ('postal_district', '=', False),
        ]
        partners = self.search(domain, limit=batch_size)
        if not partners:
            return

        pincode_cache = {}

        for partner in partners:
            raw_pin = (partner.zip or '').strip()
            if raw_pin.endswith('.0'):
                raw_pin = raw_pin[:-2].strip()
            if len(raw_pin) != 6 or not raw_pin.isdigit():
                continue

            if raw_pin not in pincode_cache:
                pincode_cache[raw_pin] = self._fetch_postal_info(raw_pin)

            info = pincode_cache[raw_pin]
            if not info:
                continue

            area = self._match_postal_locality(partner, info.get('localities', []))
            district = info.get('district') or False
            city = info.get('taluk') or False

            vals = {}
            if district and not partner.postal_district:
                vals['postal_district'] = district
            if city and not partner.postal_city:
                vals['postal_city'] = city
            if area and not partner.postal_area:
                vals['postal_area'] = area

            if vals:
                partner.write(vals)
