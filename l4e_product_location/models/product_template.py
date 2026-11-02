# -*- coding: utf-8 -*-
from odoo import fields, models


class ProductTemplate(models.Model):
    _inherit = 'product.template'

    product_type = fields.Selection(
        selection=[
            ('raw_material', 'Raw materials'),
            ('packing_product', 'Packing products'),
        ],
        string='Product Type',
        index=True,
        help="Specify whether this product is a Raw material (routes to Storage (Godown) on purchase) "
             "or a Packing product (routes to Bottling on purchase).",
    )


class ProductProduct(models.Model):
    _inherit = 'product.product'

    product_type = fields.Selection(
        related='product_tmpl_id.product_type',
        string='Product Type',
        store=True,
        readonly=False,
    )
