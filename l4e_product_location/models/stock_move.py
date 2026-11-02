# -*- coding: utf-8 -*-
from odoo import api, fields, models


class StockMove(models.Model):
    _inherit = 'stock.move'

    product_type = fields.Selection(
        related='product_id.product_type',
        string='Product Type',
        readonly=True,
    )

    def _get_custom_destination_location(self):
        self.ensure_one()
        godown_loc = self.env.ref('l4e_product_location.location_storage_godown', raise_if_not_found=False)
        bottling_loc = self.env.ref('l4e_product_location.location_bottling', raise_if_not_found=False)

        if self.product_id.product_type == 'raw_material' and godown_loc:
            return godown_loc
        elif self.product_id.product_type == 'packing_product' and bottling_loc:
            return bottling_loc
        return False

    @api.model_create_multi
    def create(self, vals_list):
        godown_loc = self.env.ref('l4e_product_location.location_storage_godown', raise_if_not_found=False)
        bottling_loc = self.env.ref('l4e_product_location.location_bottling', raise_if_not_found=False)

        for vals in vals_list:
            purchase_line_id = vals.get('purchase_line_id')
            picking_id = vals.get('picking_id')
            is_incoming = bool(purchase_line_id)

            if not is_incoming and picking_id:
                picking = self.env['stock.picking'].browse(picking_id)
                if picking.picking_type_code == 'incoming':
                    is_incoming = True

            if is_incoming and vals.get('product_id'):
                product = self.env['product.product'].browse(vals['product_id'])
                if product.product_type == 'raw_material' and godown_loc:
                    vals['location_dest_id'] = godown_loc.id
                elif product.product_type == 'packing_product' and bottling_loc:
                    vals['location_dest_id'] = bottling_loc.id

        return super().create(vals_list)

    @api.onchange('product_id')
    def _onchange_product_id_set_custom_dest_location(self):
        is_incoming = (
            (self.picking_type_id and self.picking_type_id.code == 'incoming') or
            (self.picking_id and self.picking_id.picking_type_code == 'incoming') or
            bool(self.purchase_line_id)
        )
        if is_incoming and self.product_id:
            custom_loc = self._get_custom_destination_location()
            if custom_loc:
                self.location_dest_id = custom_loc

    def _prepare_move_line_vals(self, quantity=None, reserved_quant=None):
        vals = super()._prepare_move_line_vals(quantity=quantity, reserved_quant=reserved_quant)
        if self.location_dest_id:
            vals['location_dest_id'] = self.location_dest_id.id
        return vals
