from odoo import fields, models


class ResCompany(models.Model):
    _inherit = 'res.company'

    ff_instagram = fields.Char(
        string='Instagram',
        help='The full link to the company Instagram page. It is shown, and opens when tapped, on the '
             'Company Details of the field app profile.')
