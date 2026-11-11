# -*- coding: utf-8 -*-
import logging
from odoo import models, fields, api, _

_logger = logging.getLogger(__name__)


class BrewingTea(models.Model):
    _name = 'brewing.tea'
    _description = 'Brewing Tea Master'
    _inherit = ['mail.thread', 'mail.activity.mixin']
    _order = 'preparation_date desc, id desc'

    def _default_product_id(self):
        rec = self.env.ref('l4e_brewing_tea.product_brewed_tea', raise_if_not_found=False)
        if rec:
            if rec._name == 'product.template':
                return rec.product_variant_id
            return rec
        prod = self.env['product.product'].search([('name', '=', 'Brewed Tea')], limit=1)
        if prod:
            return prod
        return self.env['product.product'].search([], limit=1)

    name = fields.Char(
        string='SI No',
        required=True,
        copy=False,
        readonly=True,
        index=True,
        default=lambda self: _('New'),
        tracking=True,
    )
    product_id = fields.Many2one(
        'product.product',
        string='Product',
        default=_default_product_id,
        required=True,
        tracking=True,
        help="Brewed tea product maintained in stock.",
    )
    uom_id = fields.Many2one(
        'uom.uom',
        string='Unit of Measure',
        related='product_id.uom_id',
        readonly=True,
    )
    preparation_date = fields.Date(
        string='Preparation Date',
        default=fields.Date.context_today,
        required=True,
        tracking=True,
        help="Date on which the tea brewing batch was prepared.",
    )
    quantity = fields.Float(
        string='Quantity',
        digits='Product Unit of Measure',
        default=0.0,
        required=True,
        tracking=True,
        help="Quantity produced or brewed for this batch.",
    )
    qc_status = fields.Selection(
        [
            ('pass', 'Pass'),
            ('fail', 'Fail'),
        ],
        string='Overall QC',
        compute='_compute_qc_status',
        store=True,
        tracking=True,
    )
    qc_summary = fields.Char(
        string='QC Details',
        compute='_compute_qc_summary',
        store=True,
        help="Status of each quality check description (e.g. Tea: Fail | Coffee: Pass).",
    )
    stock_recorded = fields.Boolean(
        string='Stock Recorded in Godown',
        default=False,
        readonly=True,
        copy=False,
        tracking=True,
        help="Indicates whether the produced brewed tea has been placed into Storage (Godown) stock.",
    )
    stock_picking_id = fields.Many2one(
        'stock.picking',
        string='Stock Receipt',
        readonly=True,
        copy=False,
        tracking=True,
        help="Internal transfer / receipt recording initial stock of brewed tea in Storage (Godown).",
    )
    user_id = fields.Many2one(
        'res.users',
        string='Responsible / Prepared By',
        default=lambda self: self.env.user,
        tracking=True,
    )
    company_id = fields.Many2one(
        'res.company',
        string='Company',
        default=lambda self: self.env.company,
        required=True,
    )
    qc_line_ids = fields.One2many(
        'brewing.tea.qc.line',
        'brewing_id',
        string='Quality Check Lines',
        copy=True,
    )

    @api.onchange('qc_line_ids')
    def _onchange_qc_line_ids_resequence(self):
        for idx, line in enumerate(self.qc_line_ids, start=1):
            line.sl_no = idx

    @api.depends('qc_line_ids.status')
    def _compute_qc_status(self):
        for rec in self:
            if not rec.qc_line_ids:
                rec.qc_status = False
                continue
            all_statuses = [line.status for line in rec.qc_line_ids]
            if any(st == 'fail' for st in all_statuses):
                rec.qc_status = 'fail'
            elif all(st == 'pass' for st in all_statuses):
                rec.qc_status = 'pass'
            else:
                rec.qc_status = False

    @api.depends('qc_line_ids.description', 'qc_line_ids.status')
    def _compute_qc_summary(self):
        for rec in self:
            if not rec.qc_line_ids:
                rec.qc_summary = ''
                continue
            items = []
            for line in rec.qc_line_ids:
                status_str = 'Pass' if line.status == 'pass' else 'Fail'
                desc = line.description or ''
                items.append(f"{desc}: {status_str}")
            rec.qc_summary = "  •  ".join(items)

    def _record_brewed_tea_stock(self):
        """
        Record the brewed tea stock into Storage (Godown) once QC passes.
        Creates and validates a stock picking from Production to Storage (Godown).
        """
        self.ensure_one()
        if self.stock_recorded or not self.product_id or self.quantity <= 0:
            return

        godown = self.env.ref('l4e_product_location.location_storage_godown', raise_if_not_found=False)
        if not godown:
            godown = self.env['stock.location'].search([('name', '=', 'Storage (Godown)')], limit=1)
        if not godown:
            warehouse = self.env['stock.warehouse'].search([('company_id', '=', self.company_id.id)], limit=1)
            godown = warehouse.lot_stock_id if warehouse else self.env.ref('stock.stock_location_stock', raise_if_not_found=False)

        prod_loc = self.env.ref('stock.stock_location_production', raise_if_not_found=False)
        if not prod_loc:
            prod_loc = self.env['stock.location'].search([('usage', '=', 'production')], limit=1)

        warehouse = self.env['stock.warehouse'].search([('company_id', '=', self.company_id.id)], limit=1)
        picking_type = warehouse.in_type_id if warehouse else self.env['stock.picking.type'].search([
            ('code', '=', 'incoming'),
            ('warehouse_id.company_id', '=', self.company_id.id),
        ], limit=1)

        move_fields = self.env['stock.move']._fields
        move_val = {
            'product_id': self.product_id.id,
            'product_uom_qty': self.quantity,
            'location_id': prod_loc.id if prod_loc else False,
            'location_dest_id': godown.id if godown else False,
            'company_id': self.company_id.id,
        }
        if 'product_uom' in move_fields:
            move_val['product_uom'] = self.uom_id.id or self.product_id.uom_id.id
        elif 'product_uom_id' in move_fields:
            move_val['product_uom_id'] = self.uom_id.id or self.product_id.uom_id.id

        if 'description_picking' in move_fields:
            move_val['description_picking'] = f"Brewed Tea Batch {self.name}"
        elif 'name' in move_fields:
            move_val['name'] = f"Brewed Tea Batch {self.name}"

        picking_vals = {
            'picking_type_id': picking_type.id if picking_type else False,
            'location_id': prod_loc.id if prod_loc else False,
            'location_dest_id': godown.id if godown else False,
            'origin': f"Brewing Batch {self.name}",
            'company_id': self.company_id.id,
            'move_ids': [(0, 0, move_val)],
        }
        try:
            picking = self.env['stock.picking'].create(picking_vals)
            picking.action_confirm()
            for move in picking.move_ids:
                move.quantity = move.product_uom_qty
            picking.button_validate()
            self.write({
                'stock_recorded': True,
                'stock_picking_id': picking.id,
            })
            _logger.info("Recorded %s L of %s in Godown for %s", self.quantity, self.product_id.display_name, self.name)
        except Exception as e:
            _logger.warning("Could not auto-validate stock receipt for brewing batch %s: %s", self.name, e)

    def action_view_stock_picking(self):
        self.ensure_one()
        return {
            'name': _('Stock Receipt for %s', self.name),
            'type': 'ir.actions.act_window',
            'res_model': 'stock.picking',
            'view_mode': 'form',
            'res_id': self.stock_picking_id.id,
        }

    @api.model_create_multi
    def create(self, vals_list):
        for vals in vals_list:
            if not vals.get('name') or vals.get('name') == _('New'):
                vals['name'] = self.env['ir.sequence'].next_by_code('brewing.tea') or _('New')
        records = super().create(vals_list)
        for rec in records:
            if rec.qc_status == 'pass' and not rec.stock_recorded:
                rec._record_brewed_tea_stock()
        return records

    def write(self, vals):
        res = super().write(vals)
        for rec in self:
            if rec.qc_status == 'pass' and not rec.stock_recorded:
                rec._record_brewed_tea_stock()
        return res
