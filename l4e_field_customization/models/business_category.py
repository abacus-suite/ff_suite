from odoo import models, fields


class BusinessCategory(models.Model):
    _name = 'business.category'
    _description = 'Business Category'
    _order = 'name'

    name = fields.Char(string='Name', required=True)
    active = fields.Boolean(default=True)
