# -*- coding: utf-8 -*-
from odoo import models, fields, api, _
from odoo.exceptions import UserError


class FermentationTransferWizard(models.TransientModel):
    _name = 'fermentation.transfer.wizard'
    _description = 'Transfer Brewing Tea to Fermentation Tank'

    brewing_id = fields.Many2one(
        'brewing.tea',
        string='Brewing Tea Batch',
        required=True,
    )
    product_id = fields.Many2one(
        'product.product',
        string='Product',
        related='brewing_id.product_id',
        readonly=True,
    )
    uom_id = fields.Many2one(
        'uom.uom',
        string='Unit of Measure',
        related='brewing_id.uom_id',
        readonly=True,
    )
    tank_id = fields.Many2one(
        'fermentation.tank',
        string='Fermentation Tank',
        required=True,
        domain=[('state', '=', 'available')],
        default=lambda self: self._default_available_tank(),
        help="Select an available tank from the 52 fermentation tanks.",
    )
    preparation_date = fields.Date(
        string='Preparation Date',
        required=True,
        default=fields.Date.context_today,
    )
    transfer_date = fields.Date(
        string='Transfer Date',
        required=True,
        default=fields.Date.context_today,
    )
    quantity = fields.Float(
        string='Quantity (L)',
        digits='Product Unit of Measure',
        required=True,
        default=0.0,
    )

    def _default_available_tank(self):
        return self.env['fermentation.tank'].search([('state', '=', 'available')], limit=1)

    def action_confirm_transfer(self):
        self.ensure_one()
        if self.brewing_id and self.brewing_id.qc_status != 'pass':
            raise UserError(_("Cannot transfer to fermentation: Brewing Tea Quality Check has not passed for batch %s.", self.brewing_id.name))

        if not self.tank_id:
            raise UserError(_("Please select a fermentation tank."))

        if self.tank_id.state != 'available':
            raise UserError(_("Tank %s is currently not available.", self.tank_id.name))

        # Ensure stock is recorded in Godown if not already done
        if hasattr(self.brewing_id, '_record_brewed_tea_stock') and not self.brewing_id.stock_recorded:
            self.brewing_id._record_brewed_tea_stock()

        # Create fermentation process record
        process = self.env['fermentation.process'].create({
            'tank_id': self.tank_id.id,
            'brewing_id': self.brewing_id.id,
            'product_id': self.product_id.id if self.product_id else False,
            'preparation_date': self.preparation_date,
            'transfer_date': self.transfer_date,
            'quantity': self.quantity,
            'uom_id': self.uom_id.id if self.uom_id else False,
            'state': 'draft',
        })

        # Automatically execute transfer and set tank to occupied
        process.action_validate_transfer()

        return {
            'name': _('Fermentation Process'),
            'type': 'ir.actions.act_window',
            'res_model': 'fermentation.process',
            'view_mode': 'form',
            'res_id': process.id,
            'target': 'current',
        }
