# -*- coding: utf-8 -*-
import logging
from odoo import api, models

_logger = logging.getLogger(__name__)


class StockPicking(models.Model):
    _inherit = 'stock.picking'

    def _update_custom_destination_header(self):
        godown = self.env.ref('l4e_product_location.location_storage_godown', raise_if_not_found=False)
        bottling = self.env.ref('l4e_product_location.location_bottling', raise_if_not_found=False)
        for picking in self:
            if picking.picking_type_code != 'incoming':
                continue
            raw_moves = picking.move_ids.filtered(lambda m: m.product_id.product_type == 'raw_material')
            pack_moves = picking.move_ids.filtered(lambda m: m.product_id.product_type == 'packing_product')
            if raw_moves and not pack_moves and godown:
                picking.location_dest_id = godown.id
            elif pack_moves and not raw_moves and bottling:
                picking.location_dest_id = bottling.id
            elif raw_moves and godown:
                picking.location_dest_id = godown.id

    @api.model_create_multi
    def create(self, vals_list):
        pickings = super().create(vals_list)
        for picking in pickings:
            if picking.picking_type_code == 'incoming' and picking.move_ids:
                picking._update_custom_destination_header()
        return pickings

    @api.model
    def _fix_existing_incoming_destinations(self):
        """
        Runs on module install / upgrade to sync picking headers with their move lines.
        Ensures existing receipts like WH/IN/00007 correctly reflect Storage (Godown) or Bottling.
        """
        godown = self.env.ref('l4e_product_location.location_storage_godown', raise_if_not_found=False)
        bottling = self.env.ref('l4e_product_location.location_bottling', raise_if_not_found=False)
        if not (godown or bottling):
            return

        incoming_pickings = self.search([('picking_type_code', '=', 'incoming')])
        updated_count = 0
        for picking in incoming_pickings:
            raw_moves = picking.move_ids.filtered(lambda m: m.product_id.product_type == 'raw_material')
            pack_moves = picking.move_ids.filtered(lambda m: m.product_id.product_type == 'packing_product')
            new_dest_id = False
            if raw_moves and not pack_moves and godown:
                new_dest_id = godown.id
            elif pack_moves and not raw_moves and bottling:
                new_dest_id = bottling.id
            elif raw_moves and godown:
                new_dest_id = godown.id

            if new_dest_id and picking.location_dest_id.id != new_dest_id:
                picking.sudo().write({'location_dest_id': new_dest_id})
                updated_count += 1

        _logger.info("Fixed destination locations for %d incoming receipts", updated_count)
