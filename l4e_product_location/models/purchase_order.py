# -*- coding: utf-8 -*-
from odoo import models


class PurchaseOrder(models.Model):
    _inherit = 'purchase.order'

    def _prepare_picking(self):
        vals = super()._prepare_picking()
        godown = self.env.ref('l4e_product_location.location_storage_godown', raise_if_not_found=False)
        bottling = self.env.ref('l4e_product_location.location_bottling', raise_if_not_found=False)

        types = set(self.order_line.mapped('product_id.product_type')) - {False}
        if types == {'raw_material'} and godown:
            vals['location_dest_id'] = godown.id
        elif types == {'packing_product'} and bottling:
            vals['location_dest_id'] = bottling.id
        elif 'raw_material' in types and godown:
            vals['location_dest_id'] = godown.id
        return vals

    def _create_picking(self):
        res = super()._create_picking()
        godown = self.env.ref('l4e_product_location.location_storage_godown', raise_if_not_found=False)
        bottling = self.env.ref('l4e_product_location.location_bottling', raise_if_not_found=False)
        for order in self:
            for picking in order.picking_ids:
                raw_moves = picking.move_ids.filtered(lambda m: m.product_id.product_type == 'raw_material')
                pack_moves = picking.move_ids.filtered(lambda m: m.product_id.product_type == 'packing_product')
                if raw_moves and not pack_moves and godown:
                    picking.location_dest_id = godown.id
                elif pack_moves and not raw_moves and bottling:
                    picking.location_dest_id = bottling.id
                elif raw_moves and godown:
                    picking.location_dest_id = godown.id
        return res
