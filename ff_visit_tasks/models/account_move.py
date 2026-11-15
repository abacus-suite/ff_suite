from odoo import fields, models
from odoo.exceptions import UserError


class AccountMove(models.Model):
    """A credit note made from the field (a sample collection) is posted by the accounts team only after the
    manager has approved it."""
    _inherit = 'account.move'

    ff_approval_state = fields.Selection([
        ('pending', 'Waiting for Manager Approval'), ('approved', 'Manager Approved'), ('rejected', 'Rejected'),
    ], string='Field Force Approval', copy=False, tracking=True, index=True,
        help='Set on credit notes made from field work: they cannot be posted until the manager approves.')

    def _post(self, soft=True):
        waiting = self.filtered(lambda m: m.ff_approval_state in ('pending', 'rejected'))
        if waiting:
            names = ', '.join((m.name if m.name and m.name != '/' else (m.ref or 'draft')) for m in waiting)
            raise UserError(self.env._(
                'The manager must approve this field credit note before it can be posted (%s).', names))
        return super()._post(soft)
