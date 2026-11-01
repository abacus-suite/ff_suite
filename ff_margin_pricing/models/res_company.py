from odoo import fields, models


class ResCompany(models.Model):
    _inherit = 'res.company'

    ff_total_margin = fields.Float(
        string='Company Margin %', digits=(5, 2),
        help='Distributors buy from the company at MRP less this. An outlet margin above its distributor margin '
             'is made good to the distributor with a debit note.')
