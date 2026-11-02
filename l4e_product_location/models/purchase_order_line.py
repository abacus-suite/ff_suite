# -*- coding: utf-8 -*-
from odoo import models


class PurchaseOrderLine(models.Model):
    _inherit = 'purchase.order.line'

    def _prepare_stock_moves(self, picking):
        """
        Route stock moves to custom locations based on product type:
        - Raw materials -> Storage (Godown)
        - Packing products -> Bottling
        """
        res = super()._prepare_stock_moves(picking)
        godown_loc = self.env.ref('l4e_product_location.location_storage_godown', raise_if_not_found=False)
        bottling_loc = self.env.ref('l4e_product_location.location_bottling', raise_if_not_found=False)

        for vals in res:
            product_id = vals.get('product_id')
            if not product_id:
                continue
            product = self.env['product.product'].browse(product_id)
            if product.product_type == 'raw_material' and godown_loc:
                vals['location_dest_id'] = godown_loc.id
            elif product.product_type == 'packing_product' and bottling_loc:
                vals['location_dest_id'] = bottling_loc.id

        return res
