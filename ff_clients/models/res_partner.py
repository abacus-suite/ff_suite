from odoo import api, fields, models
from odoo.exceptions import AccessError, ValidationError
from odoo.tools.safe_eval import safe_eval

from odoo.addons.ff_base.tools import get_param

APPROVAL_STATES = [
    ('approved', 'Approved'),
    ('pending', 'Pending Approval'),
    ('rejected', 'Rejected'),
]


class ResPartner(models.Model):
    _inherit = 'res.partner'

    ff_is_client = fields.Boolean(string='Field Contact', index=True,
                                  help='Visible to field staff in the mobile app.')
    ff_category_id = fields.Many2one('ff.contact.category', string='Contact Category', index=True, tracking=True)
    ff_category_type = fields.Selection(related='ff_category_id.category_type', store=True, string='Contact Type')
    ff_employee_ids = fields.Many2many('hr.employee', 'ff_partner_employee_rel', 'partner_id', 'employee_id',
                                       string='Field Employees',
                                       help='Employees who work with this contact. Only they (and their managers) see it in the app.')
    ff_district_id = fields.Many2one('ff.district', string='City / District', index=True)
    ff_client_code = fields.Char(string='Client Code', index=True, copy=False)
    ff_team_ids = fields.Many2many('ff.team', string='Teams', help='Informational grouping of the contact.')
    ff_geofence_radius = fields.Integer(string='Geofence Radius (m)',
                                        help='0 = use the default radius from Field Force settings.')
    ff_approval_state = fields.Selection(APPROVAL_STATES, string='Contact Approval',
                                         default='approved', index=True, copy=False)
    ff_created_by_employee_id = fields.Many2one('hr.employee', string='Added by (Field)',
                                                readonly=True, copy=False)
    ff_map_url = fields.Char(string='Map', compute='_compute_ff_map_url')

    @api.constrains('ff_is_client', 'ff_category_id', 'ff_employee_ids')
    def _check_ff_contact(self):
        for partner in self.filtered('ff_is_client'):
            if not partner.ff_category_id:
                raise ValidationError(self.env._('Field contact "%s" needs a contact category.', partner.display_name))
            if not partner.ff_employee_ids:
                raise ValidationError(self.env._('Field contact "%s" needs at least one field employee.', partner.display_name))

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
            partner.ff_map_url = partner._ff_has_location() and 'https://www.google.com/maps?q=%s,%s' % (
                partner.partner_latitude, partner.partner_longitude) or False

    def _ff_has_location(self):
        self.ensure_one()
        return bool(self.partner_latitude or self.partner_longitude)

    def _ff_radius(self):
        self.ensure_one()
        return self.ff_geofence_radius or get_param(self.env, 'geofence_radius')

    @api.model
    def _ff_ownership_domain(self, employee):
        """Which contacts "belong" to an employee. Other modules widen this."""
        return [('ff_employee_ids', 'in', employee._ff_scope_employees().ids)]

    @api.model
    def _ff_visible_domain(self, employee):
        """Contacts an employee may see in the app: theirs (or of people in their
        data access), in a category of their department, approved or their own
        pending ones."""
        employee = employee.sudo()
        categories = self.env['ff.contact.category'].ff_for_employee(employee)
        return [
            ('ff_is_client', '=', True),
            ('ff_category_id', 'in', categories.ids),
        ] + self._ff_ownership_domain(employee) + [
            '|', ('ff_approval_state', '=', 'approved'),
            '&', ('ff_approval_state', '=', 'pending'), ('ff_created_by_employee_id', '=', employee.id),
        ]

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
            categories = self.env['ff.contact.category'].ff_for_employee(employee)
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
            partner.activity_schedule('mail.mail_activity_data_todo', user_id=manager_user.id,
                                      summary=self.env._('Approve new field contact'))
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
