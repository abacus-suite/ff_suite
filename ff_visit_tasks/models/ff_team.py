from odoo import fields, models


class FfTeam(models.Model):
    _inherit = 'ff.team'

    ff_company_samples = fields.Boolean(
        string='Can Take Company Samples',
        help='Staff on this team may collect samples from the company\'s own stock, which is an '
             'internal stock issue and creates no demand and no debit note.')
