"""What the API answered to each app request that carried a uuid.

The app queues work while offline and sends it later; a request may also be
sent twice when an answer is lost on a weak network. Replaying the stored
answer for a uuid already seen makes every write safe to repeat, without
each model needing its own duplicate check.
"""
from datetime import timedelta

from odoo import api, fields, models

KEEP_DAYS = 30


class FfApiReceipt(models.Model):
    _name = 'ff.api.receipt'
    _description = 'Field App Request Receipt'
    _log_access = False

    uuid = fields.Char(required=True, index=True)
    employee_id = fields.Many2one('hr.employee', index=True, ondelete='cascade')
    path = fields.Char()
    status = fields.Integer()
    response = fields.Text()
    created_at = fields.Datetime(default=fields.Datetime.now, index=True)

    _uuid_uniq = models.Constraint('UNIQUE(uuid)', 'This request was already received.')

    @api.model
    def ff_find(self, uuid):
        return self.sudo().search([('uuid', '=', uuid)], limit=1) if uuid else self.browse()

    @api.model
    def ff_store(self, uuid, employee, path, status, response):
        if not uuid or self.ff_find(uuid):
            return
        self.sudo().create({'uuid': uuid, 'employee_id': employee.id if employee else False,
                            'path': path, 'status': status, 'response': response})

    @api.autovacuum
    def _gc_receipts(self):
        self.sudo().search([('created_at', '<', fields.Datetime.now() - timedelta(days=KEEP_DAYS))]).unlink()
