from odoo import fields, models


class FfDesignation(models.Model):
    _name = 'ff.designation'
    _description = 'Field Designation'
    _order = 'level, name'

    name = fields.Char(required=True)
    level = fields.Integer(default=1, help='1 = entry level. Higher numbers are more senior.')
    active = fields.Boolean(default=True)
