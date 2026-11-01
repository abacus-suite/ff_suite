from odoo import models, fields


class DistributorMrpLine(models.Model):
    _name = 'distributor.mrp.line'
    _description = 'Distributor MRP Line'
    _order = 'id'

    partner_id = fields.Many2one(
        'res.partner',
        string='Distributor',
        required=True,
        ondelete='cascade',
    )
    product_id = fields.Many2one(
        'product.template',
        string='Product',
        required=True,
    )
    mrp = fields.Float(
        string='MRP (Rs.)',
        digits='Product Price',
    )
