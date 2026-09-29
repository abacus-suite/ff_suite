"""Routes made in the field.

A route is usually drawn by the office, but the field is the side that finds
out a patch of town has been missed, or that one route has grown too big to
walk in a day. Letting them draw it there and then is the difference between a
route that exists and a note to somebody who will get to it next week.

Whether a new one is taken on trust or waits for the office to look at it is
the office's own decision, and it is a single setting.
"""
from odoo import api, fields, models
from odoo.exceptions import AccessError, UserError

APPROVAL_STATES = [
    ('approved', 'Approved'),
    ('pending', 'Pending Approval'),
    ('rejected', 'Rejected'),
]


def beats_need_approval(env):
    """Does a route drawn in the app wait for the office? Off unless set."""
    return env['ir.config_parameter'].sudo().get_param('ff_base.beat_approval') == 'True'


class FfBeatApp(models.Model):
    _inherit = 'ff.beat'

    ff_approval_state = fields.Selection(
        APPROVAL_STATES, string='Approval', default='approved', required=True, index=True, tracking=True,
        help='A route drawn in the app waits here when the office has asked to see new ones first.')
    ff_created_by_employee_id = fields.Many2one(
        'hr.employee', string='Drawn by (Field)', readonly=True, copy=False, index=True)

    def _ff_can_be_decided_by(self, employee):
        """Only somebody above whoever drew it may decide on it."""
        self.ensure_one()
        drawn_by = self.ff_created_by_employee_id
        return bool(drawn_by and employee and employee._ff_is_manager_of(drawn_by))

    # ------------------------------------------------------------------
    # From the app
    # ------------------------------------------------------------------
    @api.model
    def ff_create_from_app(self, employee, data):
        """Draw a route from the app. The city it covers is the one thing it must have."""
        name = (data.get('name') or '').strip()
        if not name:
            raise UserError(self.env._('Give the route a name.'))
        district = self.env['ff.district'].sudo().browse(int(data.get('district_id') or 0)).exists()
        if not district:
            raise UserError(self.env._('Choose the city this route covers.'))

        company = employee.company_id
        twin = self.sudo().search([
            ('name', '=ilike', name), ('district_id', '=', district.id),
            ('company_id', 'in', (False, company.id)),
        ], limit=1)
        if twin:
            raise UserError(self.env._('"%(name)s" already covers %(city)s.',
                                       name=twin.display_name, city=district.name))

        route_type = self.env['ff.route.type'].sudo().browse(int(data.get('route_type_id') or 0)).exists()
        pending = beats_need_approval(self.env)
        beat = self.sudo().create({
            'name': name,
            'code': (data.get('code') or '').strip() or False,
            'district_id': district.id,
            'state_id': district.state_id.id,
            'country_id': district.country_id.id,
            'route_type_id': route_type.id or False,
            'team_id': employee.ff_team_id.id or False,
            'company_id': company.id,
            'employee_ids': [(6, 0, employee.ids)],
            'ff_created_by_employee_id': employee.id,
            'ff_approval_state': 'pending' if pending else 'approved',
        })
        if pending:
            manager = employee.parent_id.user_id
            if manager:
                beat.activity_schedule(
                    'mail.mail_activity_data_todo', user_id=manager.id,
                    summary=self.env._('New route to approve: %s', beat.display_name))
        return beat

    @api.model
    def ff_add_customers_from_app(self, employee, beat, partner_ids):
        """Put customers on a route, at the end of it, skipping any already there."""
        beat = beat.sudo()
        if beat.ff_approval_state == 'rejected':
            raise UserError(self.env._('%s was turned down; it cannot be used.', beat.display_name))
        allowed = employee.sudo().ff_route_ids
        mine = beat.ff_created_by_employee_id == employee or employee in beat.employee_ids
        shared = self.env['res.partner']._ff_contact_access() == 'open'
        if not (mine or shared or not allowed or beat in allowed):
            raise AccessError(self.env._('%s is not one of your routes.', beat.display_name))

        Partner = self.env['res.partner'].sudo()
        wanted = Partner.search(
            Partner._ff_visible_domain(employee) + [('id', 'in', [int(p) for p in partner_ids or []])])
        if not wanted:
            raise UserError(self.env._('Choose the customers to put on this route.'))
        already = beat.line_ids.partner_id
        sequence = max(beat.line_ids.mapped('sequence') or [0])
        Line = self.env['ff.beat.line'].sudo()
        added = Line.browse()
        for partner in wanted - already:
            sequence += 10
            added |= Line.create({'beat_id': beat.id, 'partner_id': partner.id, 'sequence': sequence})
        return added

    def ff_app_payload(self):
        self.ensure_one()
        return {
            'id': self.id,
            'name': self.display_name,
            'code': self.code or None,
            'city': self.district_id.name or None,
            'district_id': self.district_id.id or None,
            'route_type': self.route_type_id.name or None,
            'customer_count': len(self.line_ids),
            'approval_state': self.ff_approval_state,
            'mine': self.ff_created_by_employee_id.id or None,
        }

    # ------------------------------------------------------------------
    # The office decides
    # ------------------------------------------------------------------
    def action_ff_approve(self):
        self._ff_decide(True)

    def action_ff_reject(self):
        self._ff_decide(False)

    def _ff_decide(self, approve):
        for beat in self:
            if beat.ff_approval_state != 'pending':
                raise UserError(self.env._('%s is not waiting for a decision.', beat.display_name))
        self.sudo().write({'ff_approval_state': 'approved' if approve else 'rejected'})
        self.activity_ids.unlink()

    def ff_decide_from_app(self, employee, approve):
        """A manager approves a route their own field drew."""
        self.ensure_one()
        if not self._ff_can_be_decided_by(employee):
            raise AccessError(self.env._('This route is outside your data access.'))
        self._ff_decide(approve)
        return self
