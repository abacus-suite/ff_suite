from odoo import fields, models


class ResConfigSettings(models.TransientModel):
    _inherit = 'res.config.settings'

    ff_expense_request_approval = fields.Selection([
        ('manager', 'Manager only (single approval - completes once approved)'),
        ('accounts', 'Manager, then Accounts (two-level approval - goes to accounts to pay)'),
    ], string='Payment Request Approval',
        config_parameter='ff_expenses.request_approval_levels',
        default='manager',
        help='Choose whether Expense Payment Requests complete once the reporting manager approves, '
             'or require a second approval step by the Accounts team.')
