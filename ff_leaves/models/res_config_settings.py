from odoo import fields, models


class ResConfigSettings(models.TransientModel):
    _inherit = 'res.config.settings'

    ff_leave_cancel_approval = fields.Boolean(
        string='Cancelling an Approved Leave Needs Approval', config_parameter='ff_leaves.cancel_needs_approval',
        help='When an employee with an approved leave wants to work that day and cancels it, the cancellation is '
             'sent for approval. Off: the leave is cancelled at once. Either way the employee can check in.')
    ff_leave_cancel_levels = fields.Selection(
        [('1', '1 - the manager only'), ('2', '2 - the manager, then HR (the Time Off approver)')],
        string='Approvals for a Cancellation', config_parameter='ff_leaves.cancel_levels', default='1')
