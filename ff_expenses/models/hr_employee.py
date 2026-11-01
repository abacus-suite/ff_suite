from odoo import fields, models


class HrEmployee(models.Model):
    _inherit = 'hr.employee'

    ff_expense_card_user = fields.Boolean(
        string='Company Card User',
        help='Offers Expense Submission (expenses paid with a company card) in the app.')
