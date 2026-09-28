"""What the app shows in its bell.

Odoo tells people through the chatter and their activity list, which works at a
desk. A field officer lives in the app, so the same news is written here as
well: one row per person per event, read when they open it.
"""
from datetime import timedelta

from odoo import api, fields, models

KINDS = [
    ('approval', 'Waiting for you'),
    ('decision', 'Decision on your request'),
    ('info', 'Information'),
]


class FfNotification(models.Model):
    _name = 'ff.notification'
    _description = 'Field App Notification'
    _order = 'create_date desc, id desc'

    employee_id = fields.Many2one('hr.employee', required=True, index=True, ondelete='cascade')
    user_id = fields.Many2one('res.users', string='Odoo User', index=True, ondelete='cascade')
    title = fields.Char(required=True)
    body = fields.Text()
    kind = fields.Selection(KINDS, default='info', required=True, index=True)
    res_model = fields.Char()
    res_id = fields.Integer()
    read_at = fields.Datetime(index=True)
    company_id = fields.Many2one(related='employee_id.company_id', store=True)

    @api.model
    def ff_push(self, title, body, kind='info', employee=None, user=None, record=None):
        """Write one notification for whoever this concerns.

        Either an employee or a user is enough: the other is filled in from it,
        because an approver is an Odoo user who may also be an employee, and a
        claimant is an employee who may not have a login at all.
        """
        if user and not employee:
            employee = user.sudo().employee_id
        if employee and not user:
            user = employee.sudo().user_id
        if not employee:
            return self.browse()  # nobody in the app to tell
        return self.sudo().create({
            'employee_id': employee.id,
            'user_id': user.id if user else False,
            'title': title,
            'body': body,
            'kind': kind,
            'res_model': record._name if record else False,
            'res_id': record.id if record else False,
        })

    @api.model
    def ff_for(self, employee, unread_only=False, limit=50):
        domain = [('employee_id', '=', employee.id)]
        if unread_only:
            domain.append(('read_at', '=', False))
        return self.sudo().search(domain, limit=limit)

    def ff_mark_read(self):
        self.sudo().filtered(lambda row: not row.read_at).write({'read_at': fields.Datetime.now()})
        return True

    def ff_payload(self):
        self.ensure_one()
        return {
            'id': self.id,
            'title': self.title,
            'body': self.body or '',
            'kind': self.kind,
            'at': fields.Datetime.to_string(self.create_date),
            'read': bool(self.read_at),
            'model': self.res_model or None,
            'res_id': self.res_id or None,
        }

    @api.autovacuum
    def _gc_notifications(self):
        """A notification read two months ago is of no use to anybody."""
        limit = fields.Datetime.now() - timedelta(days=60)
        self.sudo().search([('read_at', '<', limit)]).unlink()
