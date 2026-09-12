"""Time off, seen from the field app.

Odoo already models leave properly - types, allocations, approval steps - so the
app asks it questions rather than keeping its own version of the truth.
"""
from odoo import api, fields, models
from odoo.exceptions import AccessError, UserError

APP_STATES = {
    'draft': 'Draft',
    'confirm': 'Waiting approval',
    'refuse': 'Refused',
    'validate1': 'Second approval',
    'validate': 'Approved',
    'cancel': 'Cancelled',
}


class HrLeave(models.Model):
    _inherit = 'hr.leave'

    def ff_app_payload(self):
        self.ensure_one()
        return {
            'id': self.id,
            'type': {'id': self.holiday_status_id.id, 'name': self.holiday_status_id.name},
            'from': self.request_date_from and self.request_date_from.isoformat(),
            'to': self.request_date_to and self.request_date_to.isoformat(),
            'days': self.number_of_days,
            'half_day': self.request_unit_half,
            'state': self.state,
            'state_label': APP_STATES.get(self.state, self.state),
            'reason': self.private_name or self.name or '',
            'employee': {'id': self.employee_id.id, 'name': self.employee_id.name},
            'can_cancel': self.state in ('draft', 'confirm'),
        }

    # ------------------------------------------------------------------
    @api.model
    def ff_types_for(self, employee):
        """Leave types this employee may ask for, with what is left of each."""
        Type = self.env['hr.leave.type'].sudo().with_context(
            employee_id=employee.id, default_employee_id=employee.id)
        types = Type.search([('company_id', 'in', (False, employee.company_id.id))])
        rows = []
        for leave_type in types:
            rows.append({
                'id': leave_type.id,
                'name': leave_type.name,
                'requires_allocation': leave_type.requires_allocation == 'yes',
                'remaining': round(leave_type.virtual_remaining_leaves or 0.0, 2),
                'unit': leave_type.request_unit,
                'colour': leave_type.color or 0,
            })
        return rows

    @api.model
    def ff_my_leaves(self, employee, limit=50):
        leaves = self.sudo().search([('employee_id', '=', employee.id)],
                                    order='request_date_from desc', limit=limit)
        return [leave.ff_app_payload() for leave in leaves]

    @api.model
    def ff_request_from_app(self, employee, data):
        """Raise a leave request for this employee, as that employee."""
        leave_type = self.env['hr.leave.type'].sudo().browse(int(data.get('type_id') or 0)).exists()
        if not leave_type:
            raise UserError(self.env._('Choose a leave type.'))
        date_from = fields.Date.to_date(data.get('from'))
        date_to = fields.Date.to_date(data.get('to')) or date_from
        if not date_from:
            raise UserError(self.env._('Choose the days you are asking for.'))
        if date_to < date_from:
            date_from, date_to = date_to, date_from
        values = {
            'holiday_status_id': leave_type.id,
            'employee_id': employee.id,
            'request_date_from': date_from,
            'request_date_to': date_to,
            'name': (data.get('reason') or '').strip() or self.env._('Requested from the app'),
        }
        if data.get('half_day'):
            values.update({'request_unit_half': True, 'request_date_to': date_from})
        leave = self.sudo().with_context(
            mail_create_nosubscribe=True, leave_skip_date_check=True).create(values)
        return leave

    @api.model
    def ff_to_approve(self, employee):
        """What this manager has waiting, inside their data access."""
        team = employee._ff_subordinates()
        if not team:
            return []
        leaves = self.sudo().search([
            ('employee_id', 'in', team.ids), ('state', 'in', ('confirm', 'validate1')),
        ], order='request_date_from')
        return [leave.ff_app_payload() for leave in leaves]

    def ff_decide_as(self, employee, approve, reason=''):
        """Approve or refuse, with the manager's own rights checked first."""
        self.ensure_one()
        if self.employee_id not in employee._ff_subordinates():
            raise AccessError(self.env._('This request is not yours to decide.'))
        leave = self.sudo()
        if approve:
            leave.action_approve()
        else:
            leave.action_refuse()
            if reason:
                leave.message_post(body=reason)
        return leave

    def ff_cancel_as(self, employee):
        self.ensure_one()
        if self.employee_id != employee:
            raise AccessError(self.env._('This request is not yours.'))
        if self.state not in ('draft', 'confirm'):
            raise UserError(self.env._('An approved request cannot be withdrawn from the app.'))
        self.sudo().unlink()
        return True
