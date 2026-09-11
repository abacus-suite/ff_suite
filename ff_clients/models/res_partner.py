from odoo import api, fields, models
from odoo.exceptions import AccessError

from odoo.addons.ff_base.tools import get_param

APPROVAL_STATES = [
    ('approved', 'Approved'),
    ('pending', 'Pending Approval'),
    ('rejected', 'Rejected'),
]


class ResPartner(models.Model):
    _inherit = 'res.partner'

    ff_is_client = fields.Boolean(string='Field Client', index=True,
                                  help='Visible to field staff in the mobile app.')
    ff_client_code = fields.Char(string='Client Code', index=True, copy=False)
    ff_team_ids = fields.Many2many('ff.team', string='Visible to Teams',
                                   help='Leave empty to show the client to every team.')
    ff_geofence_radius = fields.Integer(string='Geofence Radius (m)',
                                        help='0 = use the default radius from Field Force settings.')
    ff_approval_state = fields.Selection(APPROVAL_STATES, string='Client Approval',
                                         default='approved', index=True, copy=False)
    ff_created_by_employee_id = fields.Many2one('hr.employee', string='Added by (Field)',
                                                readonly=True, copy=False)
    ff_map_url = fields.Char(string='Map', compute='_compute_ff_map_url')

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
    def _ff_visible_domain(self, employee):
        """Clients an officer may see: approved ones of their team (or of all
        teams) plus the ones they added themselves that await approval."""
        team = employee.ff_team_id
        return [
            ('ff_is_client', '=', True),
            '|', ('ff_approval_state', '=', 'approved'),
            '&', ('ff_approval_state', '=', 'pending'), ('ff_created_by_employee_id', '=', employee.id),
            '|', ('ff_team_ids', '=', False), ('ff_team_ids', 'in', team.ids),
        ]

    @api.model
    def ff_create_from_app(self, employee, vals):
        auto_approve = employee.user_id.has_group('ff_base.group_ff_manager')
        vals = dict(
            vals,
            ff_is_client=True,
            ff_approval_state='approved' if auto_approve else 'pending',
            ff_created_by_employee_id=employee.id,
            ff_team_ids=[(6, 0, employee.ff_team_id.ids)],
        )
        if not vals.get('parent_id'):
            vals.setdefault('is_company', True)
        partner = self.sudo().create(vals)
        manager_user = employee.parent_id.user_id
        if not auto_approve and manager_user:
            partner.activity_schedule('mail.mail_activity_data_todo', user_id=manager_user.id,
                                      summary=self.env._('Approve new field client'))
        return partner

    def _ff_check_can_approve(self):
        user = self.env.user
        if user.has_group('ff_base.group_ff_admin'):
            return
        approver = user.employee_id
        for partner in self:
            creator = partner.ff_created_by_employee_id
            if not approver or not user.has_group('ff_base.group_ff_manager') or (
                    creator and not approver._ff_is_manager_of(creator)):
                raise AccessError(self.env._('Only the field manager can approve this client.'))

    def action_ff_approve(self):
        self._ff_check_can_approve()
        self.sudo().write({'ff_approval_state': 'approved'})
        self.sudo().activity_ids.unlink()

    def action_ff_reject(self):
        self._ff_check_can_approve()
        self.sudo().write({'ff_approval_state': 'rejected'})
        self.sudo().activity_ids.unlink()
