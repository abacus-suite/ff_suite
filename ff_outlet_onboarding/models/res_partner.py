"""Outlet and distributor details, and what onboarding must have filled in.

The fields come from the client's workbook (sheets 1 and 2). A contact that is
still a lead needs little; one that is onboarded must carry GST, points of
contact, addresses, MRP, scheme, credit days, margin and so on, so those are
checked when the status becomes Onboarded - never on the thousands of contacts
that are already there.
"""
import re

from odoo import api, fields, models
from odoo.exceptions import ValidationError

GSTIN = re.compile(r'^[0-9]{2}[A-Z]{5}[0-9]{4}[A-Z][1-9A-Z]Z[0-9A-Z]$')
EMAIL = re.compile(r'^[^@\s]+@[^@\s]+\.[^@\s]+$')
PHONE = re.compile(r'^[0-9]{10}$')

STATUSES = [
    ('new_lead', 'New Lead'),
    ('onboard_pending', 'Confirmed - Details Pending'),
    ('onboarded', 'Onboarded'),
    ('stopped', 'Stopped'),
    ('not_interested', 'Not Interested'),
]


class ResPartner(models.Model):
    _inherit = 'res.partner'

    ff_status = fields.Selection(STATUSES, string='Status', index=True, tracking=True)
    ff_gst_name = fields.Char(string='Name as per GST')
    ff_poc_name = fields.Char(string='POC Name', help='Point of contact; for a distributor, the sales contact.')
    ff_poc_phone = fields.Char(string='POC Contact No.')
    ff_poc_email = fields.Char(string='POC Email')
    ff_accounts_poc_name = fields.Char(string='Accounts POC Name')
    ff_accounts_poc_phone = fields.Char(string='Accounts POC Contact No.')
    ff_accounts_poc_email = fields.Char(string='Accounts Email')
    ff_billing_address = fields.Text(string='Billing Address')
    ff_risk_level = fields.Selection([
        ('low', 'Low'),
        ('medium', 'Medium'),
        ('high', 'High'),
    ], string='Risk Category Level', default='low')
    ff_mrp_id = fields.Many2one('ff.partner.option', string='MRP', domain=[('kind', '=', 'mrp')])
    ff_door_no = fields.Char(string='Door / TC No.')
    ff_street_name = fields.Char(string='Street Name')
    ff_delivery_same_billing = fields.Boolean(string='Delivery Same as Billing')
    ff_delivery_address = fields.Text(string='Delivery Address',
                                      help='Only when the delivery address is not the billing address.')
    ff_delivery_zip = fields.Char(string='Delivery PIN Code')
    ff_delivery_region_id = fields.Many2one('ff.team', string='Delivery Region')
    ff_delivery_district_id = fields.Many2one('ff.district', string='Delivery District / Territory')
    ff_delivery_area_id = fields.Many2one('ff.area', string='Delivery Area')
    ff_delivery_door_no = fields.Char(string='Delivery Door Number')
    ff_delivery_street_name = fields.Char(string='Delivery Street Name')
    ff_has_gst = fields.Boolean(string='GST Available', default=True,
                                help='Off for an outlet with no GST: then no GSTIN is asked for.')
    ff_swiggy_zomato = fields.Boolean(string='Swiggy / Zomato Outlet')
    ff_swiggy_zomato_id = fields.Char(string='Swiggy ID / Zomato ID')
    ff_swiggy = fields.Boolean(string='On Swiggy')
    ff_swiggy_id = fields.Char(string='Swiggy ID')
    ff_zomato = fields.Boolean(string='On Zomato')
    ff_zomato_id = fields.Char(string='Zomato ID')
    ff_has_chiller = fields.Boolean(string='Chiller (from Kumbayah)')
    ff_chiller_serial = fields.Char(string='Chiller Serial Number')
    ff_chiller_model_id = fields.Many2one('ff.partner.option', string='Chiller Model',
                                          domain=[('kind', '=', 'chiller_model')])
    ff_scheme_id = fields.Many2one('ff.partner.option', string='Scheme', domain=[('kind', '=', 'scheme')])
    ff_credit_days = fields.Integer(string='Credit Days')
    ff_margin = fields.Float(string='Margin %', digits=(8, 2))
    ff_onboarded_date = fields.Date(string='Onboarded Date')
    ff_outlet_category_id = fields.Many2one('ff.partner.option', string='Outlet Category',
                                            domain=[('kind', '=', 'outlet_category')])
    ff_outlet_category_needs_note = fields.Boolean(related='ff_outlet_category_id.needs_note')
    ff_outlet_category_note = fields.Char(string='Outlet Category (Others)')
    ff_not_interested_reason = fields.Char(string='Reason for Not Interested')
    ff_terms_history_ids = fields.One2many('ff.partner.terms.history', 'partner_id', string='Scheme & Margin History')

    def _ff_lead_status(self, code):
        """Where a lead stands after a task (called by the task); kept in step with the client's own status."""
        self._ff_set_status(code)

    def _ff_set_status(self, status):
        values = {'ff_status': status}
        if 'client_status' in self._fields:
            values['client_status'] = {'onboard_pending': 'confirmed'}.get(status, status)
        self.sudo().write(values)

    # ------------------------------------------------------------------
    # What onboarding needs
    # ------------------------------------------------------------------
    @api.model
    def ff_onboarding_options(self):
        Option = self.env['ff.partner.option']
        return {
            'mrp': Option.ff_choices('mrp'),
            'schemes': Option.ff_choices('scheme'),
            'currency_symbol': self.env.company.currency_id.symbol or self.env.company.currency_id.name or '',
            'chiller_models': Option.ff_choices('chiller_model'),
            'outlet_categories': Option.ff_choices('outlet_category'),
        }

    @api.model
    def ff_set_outlet_category(self, code, note=None):
        """Called by the lead task, which knows the category by its code."""
        option = self.env['ff.partner.option'].ff_by_code('outlet_category', code)
        if option:
            self.sudo().write({'ff_outlet_category_id': option.id, 'ff_outlet_category_note': note or False})

    def ff_onboard_missing(self, kind):
        """What is still missing for this contact to be onboarded as ``kind`` (outlet or distributor)."""
        self.ensure_one()
        missing = []

        def need(value, label):
            if not (value or '').strip() if isinstance(value, str) else not value:
                missing.append(label)

        need(self.name, 'Name')
        if self.ff_has_gst is not False:
            need(self.vat, 'GSTIN')
            if self.vat and not GSTIN.match(self.vat.strip().upper()):
                missing.append('A valid 15-character GSTIN')
            need(self.ff_gst_name, 'Name as per GST')
        need(self.street, 'Delivery address')
        need(self.city, 'City')
        need(self.zip, 'Pincode')
        need(self.ff_billing_address, 'Billing address')
        need(self.ff_mrp_id, 'MRP')
        need(self.ff_scheme_id, 'Scheme')
        if self.ff_credit_days is None or self.ff_credit_days < 0:
            missing.append('Credit days')
        if not self.ff_margin:
            missing.append('Margin')
        if kind == 'outlet':
            need(self.ff_outlet_category_id, 'Outlet category')
            if self.ff_outlet_category_id.needs_note:
                need(self.ff_outlet_category_note, 'Outlet category description')
            need(self.ff_poc_name, 'POC name')
            self._ff_check_contact(self.ff_poc_phone, self.ff_poc_email, 'POC', missing, email_required=False)
            need(self.ff_distributor_id, 'Distributor')
            if self.ff_has_chiller:
                need(self.ff_chiller_serial, 'Chiller serial number')
                need(self.ff_chiller_model_id, 'Chiller model')
        else:
            need(self.ff_poc_name, 'Sales POC name')
            self._ff_check_contact(self.ff_poc_phone, self.ff_poc_email, 'Sales POC', missing, email_required=False)
            need(self.ff_accounts_poc_name, 'Accounts POC name')
            self._ff_check_contact(self.ff_accounts_poc_phone, self.ff_accounts_poc_email, 'Accounts POC', missing,
                                   email_required=False)
        return missing

    @api.model
    def _ff_check_contact(self, phone, email, label, missing, email_required=True):
        if not phone or not PHONE.match(phone.strip()):
            missing.append('%s contact number (10 digits)' % label)
        if (email_required or email) and (not email or not EMAIL.match(email.strip())):
            missing.append('%s email' % label)

    def ff_map_from_pincode(self, limit=100):
        """Existing contacts: from their PIN code, make the masters (flagged ``api_created``) and map the contact to
        its District / Territory and City / Town; the Area only when the PIN code has one locality. Run in batches."""
        resolver = self.env['ff.pincode.resolver']
        done = 0
        if self:
            # Called on chosen contacts (the list action): just those, whatever they already have; only what is empty
            # is filled.
            partners = self.sudo().filtered('zip')
        else:
            partners = self.env['res.partner'].sudo().search(
                [('ff_is_client', '=', True), ('zip', '!=', False), '|', ('ff_district_id', '=', False),
                 ('ff_area_id', '=', False)], limit=limit, order='id')
        for partner in partners:
            masters = resolver.ff_resolve(partner.zip, region=partner.ff_team_ids)
            if not masters['district']:
                continue
            vals = {}
            if not partner.ff_district_id:
                vals['ff_district_id'] = masters['district'].id
            if not partner.ff_territory_id and len(masters['cities']) == 1:
                vals['ff_territory_id'] = masters['cities'].id
            if not partner.ff_area_id and len(masters['areas']) == 1:
                vals['ff_area_id'] = masters['areas'].id
                vals.setdefault('ff_territory_id', masters['areas'].territory_id.id)
            if vals:
                partner.write(vals)
                done += 1
        return done

    @staticmethod
    def _ff_digits(number):
        """A phone number as its last ten digits, so +91 98765 43210 and 9876543210 are the same number."""
        digits = re.sub(r'\D', '', number or '')
        return digits[-10:] if len(digits) >= 10 else digits

    @api.constrains('ff_poc_phone')
    def _check_ff_poc_phone_unique(self):
        """The POC contact number belongs to one contact: it cannot be entered on a second one."""
        for partner in self:
            key = self._ff_digits(partner.ff_poc_phone)
            if not key:
                continue
            others = self.sudo().with_context(active_test=False).search(
                [('id', '!=', partner.id), ('ff_poc_phone', '!=', False)])
            clash = others.filtered(lambda o: self._ff_digits(o.ff_poc_phone) == key)[:1]
            if clash:
                raise ValidationError(self.env._(
                    'The POC contact number %(number)s is already used by %(name)s. A POC number must be unique.',
                    number=partner.ff_poc_phone, name=clash.display_name))

    @api.constrains('ff_status', 'ff_outlet_category_id', 'ff_outlet_category_note', 'ff_not_interested_reason')
    def _check_status_details(self):
        """Every status needs the outlet category; Not Interested needs its reason."""
        for partner in self.filtered(lambda p: p.ff_status in ('onboarded', 'stopped', 'not_interested')
                                     and p.ff_category_type in ('lead', 'outlet', 'distributor')):
            if partner.ff_category_type != 'distributor':
                if not partner.ff_outlet_category_id:
                    raise ValidationError(self.env._('%s: choose the outlet category.', partner.display_name))
                if partner.ff_outlet_category_id.needs_note and not partner.ff_outlet_category_note:
                    raise ValidationError(self.env._('%s: describe the outlet category (Others).',
                                                     partner.display_name))
            if partner.ff_status == 'not_interested' and not partner.ff_not_interested_reason:
                raise ValidationError(self.env._('%s: say why it is not interested.', partner.display_name))

    @api.constrains('ff_status')
    def _check_onboarded_details(self):
        for partner in self.filtered(lambda p: p.ff_status in ('onboarded', 'stopped') and p.ff_category_type in
                                     ('outlet', 'distributor')):
            missing = partner.ff_onboard_missing(partner.ff_category_type)
            if missing:
                raise ValidationError(self.env._(
                    '%(name)s cannot be Onboarded yet. Still needed: %(missing)s.',
                    name=partner.display_name, missing=', '.join(missing)))

    # ------------------------------------------------------------------
    # Scheme and margin history, with the dates each applied
    # ------------------------------------------------------------------
    def write(self, vals):
        watched = {'ff_scheme_id', 'ff_margin'} & set(vals)
        before = {p.id: (p.ff_scheme_id.id, p.ff_margin) for p in self} if watched else {}
        res = super().write(vals)
        if watched:
            for partner in self:
                old = before.get(partner.id)
                if old and (partner.ff_scheme_id.id, partner.ff_margin) != old:
                    self.env['ff.partner.terms.history']._ff_record(partner)
        return res

    @api.model_create_multi
    def create(self, vals_list):
        partners = super().create(vals_list)
        for partner in partners.filtered(lambda p: p.ff_scheme_id or p.ff_margin):
            self.env['ff.partner.terms.history']._ff_record(partner)
        return partners

    def ff_onboarding_payload(self):
        """What was taken at onboarding, for the app's edit screen."""
        self.ensure_one()
        partner = self.sudo()
        option = lambda o: {'code': o.code, 'name': o.name} if o else None  # noqa: E731
        return {
            'status': partner.ff_status or None,
            'onboarded_date': partner.ff_onboarded_date.isoformat() if partner.ff_onboarded_date else None,
            'gst_name': partner.ff_gst_name or None,
            'door_no': partner.ff_door_no or None,
            'street_name': partner.ff_street_name or None,
            'billing_address': partner.ff_billing_address or None,
            'delivery_same': bool(partner.ff_delivery_same_billing),
            'delivery_address': partner.ff_delivery_address or None,
            'delivery_zip': partner.ff_delivery_zip or None,
            'delivery_region_id': partner.ff_delivery_region_id.id or None,
            'delivery_territory_id': partner.ff_delivery_district_id.id or None,
            'delivery_area_id': partner.ff_delivery_area_id.id or None,
            'delivery_door': partner.ff_delivery_door_no or None,
            'delivery_street': partner.ff_delivery_street_name or None,
            'poc_name': partner.ff_poc_name or None,
            'poc_phone': partner.ff_poc_phone or None,
            'poc_email': partner.ff_poc_email or None,
            'accounts_poc_name': partner.ff_accounts_poc_name or None,
            'accounts_poc_phone': partner.ff_accounts_poc_phone or None,
            'accounts_poc_email': partner.ff_accounts_poc_email or None,
            'outlet_category': option(partner.ff_outlet_category_id),
            'outlet_category_note': partner.ff_outlet_category_note or None,
            'risk_level': partner.ff_risk_level or 'low',
            'mrp': option(partner.ff_mrp_id),
            'scheme': dict(option(partner.ff_scheme_id), value=partner.ff_scheme_id.ff_scheme_value())
            if partner.ff_scheme_id else None,
            'currency_symbol': (partner.company_id or self.env.company).currency_id.symbol or '',
            'distributor': {'id': partner.ff_distributor_id.id, 'name': partner.ff_distributor_id.name}
            if partner.ff_distributor_id else None,
            'has_gst': partner.ff_has_gst is not False,
            'swiggy_zomato': partner.ff_swiggy_zomato,
            'swiggy_zomato_id': partner.ff_swiggy_zomato_id or None,
            'swiggy': partner.ff_swiggy,
            'swiggy_id': partner.ff_swiggy_id or None,
            'zomato': partner.ff_zomato,
            'zomato_id': partner.ff_zomato_id or None,
            'has_chiller': partner.ff_has_chiller,
            'chiller_serial': partner.ff_chiller_serial or None,
            'chiller_model': option(partner.ff_chiller_model_id),
            'credit_days': partner.ff_credit_days,
            'margin': partner.ff_margin,
        }

    def ff_update_details(self, data):
        """Change onboarding details from the edit screen. Only what is sent is changed."""
        self.ensure_one()
        partner = self.sudo()
        Option = self.env['ff.partner.option']
        values = {}

        def text(key, field):
            if key in data:
                values[field] = (data.get(key) or '').strip() or False

        text('gst_name', 'ff_gst_name')
        text('door_no', 'ff_door_no')
        text('street_name', 'ff_street_name')
        text('billing_address', 'ff_billing_address')
        for key in ('poc', 'accounts_poc'):
            text(key + '_name', 'ff_' + key + '_name')
            text(key + '_phone', 'ff_' + key + '_phone')
            text(key + '_email', 'ff_' + key + '_email')
            if values.get('ff_%s_phone' % key) and not PHONE.match(values['ff_%s_phone' % key]):
                raise ValidationError(self.env._('The contact number must be 10 digits.'))
            if values.get('ff_%s_email' % key) and not EMAIL.match(values['ff_%s_email' % key]):
                raise ValidationError(self.env._('Enter a valid email address.'))
        text('outlet_category_note', 'ff_outlet_category_note')
        text('swiggy_zomato_id', 'ff_swiggy_zomato_id')
        text('chiller_serial', 'ff_chiller_serial')
        if 'risk_level' in data:
            values['ff_risk_level'] = data.get('risk_level') or 'low'
        for key, kind, field in (('outlet_category', 'outlet_category', 'ff_outlet_category_id'),
                                 ('mrp', 'mrp', 'ff_mrp_id'), ('scheme', 'scheme', 'ff_scheme_id'),
                                 ('chiller_model', 'chiller_model', 'ff_chiller_model_id')):
            if key in data:
                values[field] = Option.ff_by_code(kind, data.get(key)).id or False
        for key, field in (('swiggy_zomato', 'ff_swiggy_zomato'), ('has_chiller', 'ff_has_chiller')):
            if key in data:
                values[field] = bool(data.get(key))
        if 'credit_days' in data and str(data.get('credit_days')).strip() != '':
            try:
                values['ff_credit_days'] = int(float(data.get('credit_days')))
            except (TypeError, ValueError):
                raise ValidationError(self.env._('Enter the credit days as a number.'))
        if 'margin' in data and str(data.get('margin')).strip() != '':
            try:
                values['ff_margin'] = float(data.get('margin'))
            except (TypeError, ValueError):
                raise ValidationError(self.env._('Enter the margin as a number.'))
        if 'distributor_id' in data:
            distributor = self.browse(int(data.get('distributor_id') or 0)).sudo().exists()
            if distributor and not distributor.ff_is_distributor:
                raise ValidationError(self.env._('%s is not a distributor.', distributor.name))
            values['ff_distributor_id'] = distributor.id or False
        if values.get('ff_swiggy_zomato') is False:
            values['ff_swiggy_zomato_id'] = False
        if values.get('ff_has_chiller') is False:
            values.update(ff_chiller_serial=False, ff_chiller_model_id=False)
        if values:
            partner.write(values)
        return list(values)

    def ff_onboard(self, employee, kind, data):
        """Turn a lead into an outlet or a distributor, with everything the office needs."""
        self.ensure_one()
        partner = self.sudo()
        if kind not in ('outlet', 'distributor'):
            raise ValidationError(self.env._('Choose whether this is an outlet or a distributor.'))
        category = self.env['ff.contact.category'].ff_for_employee(employee).filtered(
            lambda c: c.category_type == kind)[:1]
        if not category:
            raise ValidationError(self.env._('There is no %s category for you. Ask the office.', kind))

        def text(key):
            return (data.get(key) or '').strip() or False

        def flag(key):
            return bool(data.get(key))

        has_gst = data.get('has_gst') is not False
        swiggy, zomato = flag('swiggy'), flag('zomato')
        if 'swiggy' not in data and 'zomato' not in data:
            swiggy = zomato = flag('swiggy_zomato')  # an older app: one answer for both
        values = {
            'ff_has_gst': has_gst,
            'vat': ((text('gstin') or '').upper() or False) if has_gst else False,
            'ff_gst_name': text('gst_name'),
            'street': text('street'), 'street2': text('street2'), 'city': text('city'), 'zip': text('zip'),
            'ff_door_no': text('door_no'), 'ff_street_name': text('street_name'),
            'ff_delivery_same_billing': flag('delivery_same'),
            # A delivery address of its own is kept only when it is not the billing address.
            'ff_delivery_address': False if flag('delivery_same') else text('delivery_address'),
            'ff_delivery_zip': False if flag('delivery_same') else text('delivery_zip'),
            'ff_delivery_door_no': False if flag('delivery_same') else text('delivery_door'),
            'ff_delivery_street_name': False if flag('delivery_same') else text('delivery_street'),
            'ff_billing_address': text('billing_address'),
            'ff_poc_name': text('poc_name'), 'ff_poc_phone': text('poc_phone'), 'ff_poc_email': text('poc_email'),
            'ff_risk_level': data.get('risk_level') or 'low',
            'ff_mrp_id': self.env['ff.partner.option'].ff_by_code('mrp', data.get('mrp')).id or False,
            'ff_scheme_id': self.env['ff.partner.option'].ff_by_code('scheme', data.get('scheme')).id or False,
            'ff_swiggy': swiggy, 'ff_swiggy_id': text('swiggy_id') if swiggy else False,
            'ff_zomato': zomato, 'ff_zomato_id': text('zomato_id') if zomato else False,
            # The one answer older screens and reports still read.
            'ff_swiggy_zomato': swiggy or zomato,
            'ff_swiggy_zomato_id': (text('swiggy_id') if swiggy else False) or (text('zomato_id') if zomato else False)
            or text('swiggy_zomato_id'),
        }
        # State and district, found by name (the app works them out from the PIN code).
        state = self.env['res.country.state'].sudo().search(
            [('name', '=ilike', data.get('state') or ''), ('country_id.code', '=', 'IN')], limit=1) \
            if data.get('state') else self.env['res.country.state']
        if state:
            values['state_id'] = state.id
            values['country_id'] = state.country_id.id
        district = self.env['ff.district'].sudo().search(
            [('name', '=ilike', data.get('district') or '')] + ([('state_id', '=', state.id)] if state else []),
            limit=1) if data.get('district') else self.env['ff.district']
        if district:
            values['ff_district_id'] = district.id
        # Where it sits, as chosen in the app (each one a dropdown there): region, territory, city and area.
        Partner = self.env['res.partner']
        region = self.env['ff.team'].sudo().browse(int(data.get('region_id') or 0)).exists()
        if region and 'ff_team_ids' in Partner._fields:
            values['ff_team_ids'] = [(4, region.id)]
        # The app's Territory is the District / Territory master.
        district = self.env['ff.district'].sudo().browse(
            int(data.get('territory_id') or data.get('district_id') or 0)).exists() if 'ff.district' in self.env else None
        if district and 'ff_district_id' in Partner._fields:
            values['ff_district_id'] = district.id
        # The delivery address: the same details as the billing address when it is the same, else the ones entered.
        same = flag('delivery_same')

        def pick(model, key):
            return self.env[model].sudo().browse(int(data.get(key) or 0)).exists() if model in self.env else None
        if same:
            values.update({
                'ff_delivery_address': text('billing_address'), 'ff_delivery_zip': text('zip'),
                'ff_delivery_door_no': text('door_no'), 'ff_delivery_street_name': text('street_name'),
                'ff_delivery_region_id': pick('ff.team', 'region_id').id or False,
                'ff_delivery_district_id': pick('ff.district', 'territory_id').id or pick('ff.district', 'district_id').id or False,
                'ff_delivery_area_id': pick('ff.area', 'area_id').id or False,
            })
        else:
            values.update({
                'ff_delivery_region_id': pick('ff.team', 'delivery_region_id').id or False,
                'ff_delivery_district_id': pick('ff.district', 'delivery_territory_id').id or False,
                'ff_delivery_area_id': pick('ff.area', 'delivery_area_id').id or False,
            })
        area = self.env['ff.area'].sudo().browse(int(data.get('area_id') or 0)).exists() if 'ff.area' in self.env else None
        if area and 'ff_area_id' in Partner._fields:
            values['ff_area_id'] = area.id
            # The area belongs to a City / Town: the contact takes it.
            if 'ff_territory_id' in Partner._fields and area.territory_id:
                values['ff_territory_id'] = area.territory_id.id
        city = self.env['ff.district'].sudo().browse(int(data.get('district_id') or 0)).exists()
        if city:
            values['ff_district_id'] = city.id
            values.setdefault('state_id', city.state_id.id)
            values.setdefault('country_id', city.country_id.id)
            values['city'] = values.get('city') or city.name
        try:
            values['ff_credit_days'] = int(data.get('credit_days'))
            values['ff_margin'] = float(data.get('margin'))
        except (TypeError, ValueError):
            raise ValidationError(self.env._('Enter the credit days and the margin as numbers.'))
        if kind == 'outlet':
            values.update(
                ff_outlet_category_id=self.env['ff.partner.option'].ff_by_code('outlet_category', data.get('outlet_category')).id or False,
                ff_outlet_category_note=text('outlet_category_note'),
                ff_has_chiller=flag('has_chiller'),
                ff_chiller_serial=text('chiller_serial') if flag('has_chiller') else False,
                ff_chiller_model_id=(self.env['ff.partner.option'].ff_by_code('chiller_model', data.get('chiller_model')).id or False) if flag('has_chiller') else False,
            )
            values['ff_is_distributor'] = False
            distributor = self.browse(int(data.get('distributor_id') or 0)).sudo().exists()
            if distributor and distributor.ff_is_distributor:
                values['ff_distributor_id'] = distributor.id
        else:
            # A distributor is marked as one, so it can be chosen as the supplier of outlets.
            values.update(ff_is_distributor=True, ff_distributor_id=False)
            values.update(ff_accounts_poc_name=text('accounts_poc_name'),
                          ff_accounts_poc_phone=text('accounts_poc_phone'),
                          ff_accounts_poc_email=text('accounts_poc_email'))
        if data.get('onboarded_date'):
            chosen = fields.Date.to_date(data['onboarded_date'])
            if chosen and chosen <= fields.Date.context_today(self):
                values['ff_onboarded_date'] = chosen
        # Checked before anything is saved, on what the contact would be.
        partner.write(dict(values, ff_category_id=category.id))
        missing = partner.ff_onboard_missing(kind)
        if missing:
            raise ValidationError(self.env._('Still needed: %s.', ', '.join(missing)))
        partner._ff_set_status('onboarded')
        today = partner.ff_onboarded_date or fields.Date.context_today(self)
        partner.write({'ff_onboarded_date': today})
        if 'outlet_onboard_date' in partner._fields:
            partner.outlet_onboard_date = today
        return partner


class FfPartnerTermsHistory(models.Model):
    """What scheme and margin a contact had, and from when to when."""
    _name = 'ff.partner.terms.history'
    _description = 'Scheme and Margin History'
    _order = 'partner_id, date_from desc, id desc'

    partner_id = fields.Many2one('res.partner', required=True, index=True, ondelete='cascade')
    scheme_id = fields.Many2one('ff.partner.option', string='Scheme', domain=[('kind', '=', 'scheme')])
    margin = fields.Float(digits=(8, 2))
    date_from = fields.Date(required=True, default=fields.Date.context_today)
    date_to = fields.Date()
    changed_by_id = fields.Many2one('res.users', default=lambda self: self.env.user)

    @api.model
    def _ff_record(self, partner):
        """Close the terms that were running and start the new ones today."""
        partner = partner.sudo()
        today = fields.Date.context_today(self)
        open_rows = self.sudo().search([('partner_id', '=', partner.id), ('date_to', '=', False)])
        open_rows.write({'date_to': today})
        return self.sudo().create({'partner_id': partner.id, 'scheme_id': partner.ff_scheme_id.id,
                                   'margin': partner.ff_margin, 'date_from': today})
