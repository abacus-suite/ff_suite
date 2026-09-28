from odoo import models, fields


class MarketingMaterial(models.Model):
    _name = 'marketing.material'
    _description = 'Marketing Material'
    _order = 'name'

    name = fields.Char(string='Name', required=True)
    active = fields.Boolean(default=True)
