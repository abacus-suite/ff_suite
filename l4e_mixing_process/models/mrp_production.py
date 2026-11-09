# -*- coding: utf-8 -*-
from odoo import models, fields, api, _


class MrpProduction(models.Model):
    _inherit = 'mrp.production'

    mixing_process_ids = fields.One2many(
        'mixing.process',
        'mrp_id',
        string='Mixing Processes',
    )
    mixing_process_count = fields.Integer(
        string='Mixing Processes',
        compute='_compute_mixing_process_count',
    )

    @api.depends('mixing_process_ids')
    def _compute_mixing_process_count(self):
        for rec in self:
            rec.mixing_process_count = len(rec.mixing_process_ids)

    def action_view_mixing_processes(self):
        self.ensure_one()
        return {
            'name': _('Mixing Processes for %s', self.name),
            'type': 'ir.actions.act_window',
            'res_model': 'mixing.process',
            'view_mode': 'list,form',
            'domain': [('mrp_id', '=', self.id)],
            'context': {
                'default_mrp_id': self.id,
                'default_product_id': self.product_id.id,
                'default_quantity': self.qty_produced or self.product_qty,
            },
        }

    def button_mark_done(self):
        """
        Produce All in MO:
        1. Ensures the manufactured product moves to the Mixing Area location.
        2. Automatically creates a record in the Mixing Process master in Draft stage.
        """
        mixing_loc = self.env.ref('l4e_mixing_process.location_mixing_area', raise_if_not_found=False)
        if mixing_loc:
            for mo in self:
                # Update MO destination location to Mixing Area
                if mo.location_dest_id != mixing_loc:
                    mo.location_dest_id = mixing_loc.id
                # Update finished moves destination to Mixing Area
                for move in mo.move_finished_ids:
                    move.location_dest_id = mixing_loc.id

        res = super().button_mark_done()

        # Generate draft Mixing Process records for completed MOs
        MixingProcess = self.env['mixing.process']
        for mo in self.filtered(lambda p: p.state == 'done'):
            if not mo.mixing_process_ids:
                MixingProcess.create({
                    'mrp_id': mo.id,
                    'product_id': mo.product_id.id,
                    'quantity': mo.qty_produced or mo.product_qty,
                    'uom_id': mo.product_uom_id.id,
                    'date': fields.Date.context_today(mo),
                    'state': 'draft',
                })
        return res
