# -*- coding: utf-8 -*-
from odoo import api, models


class StockMoveLine(models.Model):
    _inherit = 'stock.move.line'

    @api.model_create_multi
    def create(self, vals_list):
        for vals in vals_list:
            move_id = vals.get('move_id')
            if move_id:
                move = self.env['stock.move'].browse(move_id)
                if move.location_dest_id and move.product_id.product_type in ('raw_material', 'packing_product'):
                    vals['location_dest_id'] = move.location_dest_id.id
        return super().create(vals_list)
