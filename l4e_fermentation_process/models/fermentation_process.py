# -*- coding: utf-8 -*-
from datetime import timedelta
from odoo import models, fields, api, _
from odoo.exceptions import UserError, ValidationError


class FermentationProcess(models.Model):
    _name = 'fermentation.process'
    _description = 'Fermentation Process & Quality Tracking'
    _inherit = ['mail.thread', 'mail.activity.mixin']
    _order = 'transfer_date desc, id desc'

    name = fields.Char(
        string='Batch / Process No',
        required=True,
        copy=False,
        readonly=True,
        index=True,
        default=lambda self: _('New'),
        tracking=True,
    )
    tank_id = fields.Many2one(
        'fermentation.tank',
        string='Fermentation Tank',
        required=True,
        tracking=True,
        index=True,
        help="Select one of the 52 fermentation tanks.",
    )
    brewing_id = fields.Many2one(
        'brewing.tea',
        string='Brewing Tea Batch',
        tracking=True,
        index=True,
        help="Reference to the brewed tea batch transferred into this tank.",
    )
    product_id = fields.Many2one(
        'product.product',
        string='Product',
        help="Brewed tea product being fermented.",
    )
    preparation_date = fields.Date(
        string='Preparation Date',
        required=True,
        default=fields.Date.context_today,
        tracking=True,
        help="Date on which the tea brewing batch was originally prepared.",
    )
    transfer_date = fields.Date(
        string='Transfer Date',
        required=True,
        default=fields.Date.context_today,
        tracking=True,
        help="Date on which the brewed tea was moved to the fermentation tank.",
    )
    qc_due_date = fields.Date(
        string='15th Day QC Due Date',
        compute='_compute_qc_due_date',
        store=True,
        tracking=True,
        help="Quality check due on the 15th day of preparation (Preparation Date + 14 days).",
    )
    days_in_fermentation = fields.Integer(
        string='Days in Fermentation',
        compute='_compute_days_in_fermentation',
        help="Number of days the batch has been inside the fermentation tank.",
    )
    is_qc_due = fields.Boolean(
        string='QC Due Today / Overdue',
        compute='_compute_is_qc_due',
        search='_search_is_qc_due',
    )
    quantity = fields.Float(
        string='Quantity (L)',
        digits='Product Unit of Measure',
        default=0.0,
        required=True,
        tracking=True,
        help="Volume of brewed tea transferred to this tank.",
    )
    uom_id = fields.Many2one(
        'uom.uom',
        string='Unit of Measure',
        default=lambda self: self.env.ref('uom.product_uom_litre', raise_if_not_found=False) or self.env.ref('uom.product_uom_unit', raise_if_not_found=False),
    )
    picking_id = fields.Many2one(
        'stock.picking',
        string='Internal Transfer',
        readonly=True,
        copy=False,
        tracking=True,
        help="Stock picking for the internal transfer to Fermentation location.",
    )
    location_id = fields.Many2one(
        'stock.location',
        string='Source Location',
        default=lambda self: self._default_source_location(),
        help="Source location from which brewed tea is moved.",
    )
    location_dest_id = fields.Many2one(
        'stock.location',
        string='Destination Location',
        default=lambda self: self._default_dest_location(),
        required=True,
        help="Fermentation location.",
    )
    state = fields.Selection(
        [
            ('draft', 'Draft'),
            ('in_fermentation', 'In Fermentation'),
            ('qc_done', 'QC Done'),
            ('ready_bottling', 'Ready for Bottling'),
            ('done', 'Completed'),
            ('cancel', 'Cancelled'),
        ],
        string='Status',
        default='draft',
        required=True,
        tracking=True,
        index=True,
    )
    qc_status = fields.Selection(
        [
            ('pass', 'Pass'),
            ('fail', 'Fail'),
        ],
        string='Overall QC Status',
        compute='_compute_qc_status',
        store=True,
        tracking=True,
    )
    qc_summary = fields.Char(
        string='QC Summary',
        compute='_compute_qc_summary',
        store=True,
        help="Summary of all quality check line results.",
    )
    qc_date = fields.Date(
        string='QC Performed On',
        tracking=True,
    )
    qc_user_id = fields.Many2one(
        'res.users',
        string='QC Performed By',
        tracking=True,
    )
    qc_line_ids = fields.One2many(
        'fermentation.qc.line',
        'process_id',
        string='Quality Check Lines',
        copy=True,
    )

    @api.onchange('qc_line_ids')
    def _onchange_qc_line_ids_resequence(self):
        for idx, line in enumerate(self.qc_line_ids, start=1):
            line.sl_no = idx
    notes = fields.Html(string='Notes / Observations')
    user_id = fields.Many2one(
        'res.users',
        string='Responsible',
        default=lambda self: self.env.user,
        tracking=True,
    )
    company_id = fields.Many2one(
        'res.company',
        string='Company',
        default=lambda self: self.env.company,
        required=True,
    )

    def _default_source_location(self):
        godown = self.env.ref('l4e_product_location.location_storage_godown', raise_if_not_found=False)
        if godown:
            return godown
        warehouse = self.env['stock.warehouse'].search([('company_id', '=', self.env.company.id)], limit=1)
        return warehouse.lot_stock_id if warehouse else self.env.ref('stock.stock_location_stock', raise_if_not_found=False)

    def _default_dest_location(self):
        ferm_loc = self.env.ref('l4e_product_location.location_fermentation', raise_if_not_found=False)
        if ferm_loc:
            return ferm_loc
        return self.env['stock.location'].search([('name', '=', 'Fermentation'), ('usage', '=', 'internal')], limit=1)

    @api.depends('preparation_date')
    def _compute_qc_due_date(self):
        for rec in self:
            if rec.preparation_date:
                # 15th day of preparation (Day 1 + 14 days)
                rec.qc_due_date = rec.preparation_date + timedelta(days=14)
            else:
                rec.qc_due_date = False

    @api.depends('transfer_date')
    def _compute_days_in_fermentation(self):
        today = fields.Date.context_today(self)
        for rec in self:
            if rec.transfer_date:
                delta = (today - rec.transfer_date).days
                rec.days_in_fermentation = max(0, delta)
            else:
                rec.days_in_fermentation = 0

    @api.depends('qc_due_date', 'qc_status')
    def _compute_is_qc_due(self):
        today = fields.Date.context_today(self)
        for rec in self:
            rec.is_qc_due = bool(rec.qc_due_date and today >= rec.qc_due_date and not rec.qc_status)

    def _search_is_qc_due(self, operator, value):
        today = fields.Date.context_today(self)
        if (operator == '=' and value) or (operator == '!=' and not value):
            return [('qc_due_date', '<=', today), ('qc_status', '=', False)]
        return ['|', ('qc_due_date', '>', today), ('qc_status', '!=', False)]

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

    @api.onchange('brewing_id')
    def _onchange_brewing_id(self):
        if self.brewing_id:
            self.preparation_date = self.brewing_id.preparation_date
            if not self.quantity:
                self.quantity = self.brewing_id.quantity
            if not self.product_id and self.brewing_id.product_id:
                self.product_id = self.brewing_id.product_id
            if self.brewing_id.uom_id:
                self.uom_id = self.brewing_id.uom_id

    @api.model_create_multi
    def create(self, vals_list):
        for vals in vals_list:
            if not vals.get('name') or vals.get('name') == _('New'):
                vals['name'] = self.env['ir.sequence'].next_by_code('fermentation.process') or _('New')
        records = super().create(vals_list)
        for rec in records:
            if rec.tank_id and rec.state in ('in_fermentation', 'qc_done', 'ready_bottling'):
                rec.tank_id.write({'state': 'occupied', 'current_process_id': rec.id})
        return records

    def write(self, vals):
        res = super().write(vals)
        if 'tank_id' in vals or 'state' in vals:
            for rec in self:
                if rec.state in ('in_fermentation', 'qc_done', 'ready_bottling'):
                    if rec.tank_id:
                        rec.tank_id.write({'state': 'occupied', 'current_process_id': rec.id})
                elif rec.state in ('done', 'cancel'):
                    if rec.tank_id and rec.tank_id.current_process_id == rec:
                        rec.tank_id.write({'state': 'available', 'current_process_id': False})
        return res

    def action_validate_transfer(self):
        """
        Create and validate the internal stock transfer moving brewed tea
        to the Fermentation location, and put the process in fermentation.
        """
        for rec in self:
            rec._ensure_stock_transfer()
            if rec.tank_id:
                rec.tank_id.write({'state': 'occupied', 'current_process_id': rec.id})
            rec.write({'state': 'in_fermentation'})
        return True

    def _ensure_stock_transfer(self):
        self.ensure_one()
        if self.picking_id:
            return self.picking_id

        # Determine picking type (Internal transfer)
        warehouse = self.env['stock.warehouse'].search([('company_id', '=', self.company_id.id)], limit=1)
        picking_type = warehouse.int_type_id if warehouse else self.env['stock.picking.type'].search([
            ('code', '=', 'internal'),
            ('warehouse_id.company_id', '=', self.company_id.id),
        ], limit=1)

        source_loc = self.location_id or self._default_source_location()
        dest_loc = self.location_dest_id or self._default_dest_location()

        # Find product
        product = self.product_id or (self.brewing_id and self.brewing_id.product_id)
        if not product:
            product = self.env['product.product'].search([
                ('product_type', '=', 'raw_material'),
            ], limit=1) or self.env['product.product'].search([], limit=1)

        if not product:
            raise UserError(_("Please configure at least one product to transfer to Fermentation."))

        move_fields = self.env['stock.move']._fields
        move_val = {
            'product_id': product.id,
            'product_uom_qty': self.quantity,
            'location_id': source_loc.id if source_loc else False,
            'location_dest_id': dest_loc.id if dest_loc else False,
        }
        if 'product_uom' in move_fields:
            move_val['product_uom'] = self.uom_id.id or product.uom_id.id
        elif 'product_uom_id' in move_fields:
            move_val['product_uom_id'] = self.uom_id.id or product.uom_id.id

        if 'description_picking' in move_fields:
            move_val['description_picking'] = f"Transfer to {self.tank_id.name}"
        elif 'name' in move_fields:
            move_val['name'] = f"Transfer to {self.tank_id.name}"

        picking_vals = {
            'picking_type_id': picking_type.id if picking_type else False,
            'location_id': source_loc.id if source_loc else False,
            'location_dest_id': dest_loc.id if dest_loc else False,
            'origin': f"{self.name} - {self.tank_id.name}",
            'company_id': self.company_id.id,
            'move_ids': [(0, 0, move_val)],
        }
        picking = self.env['stock.picking'].create(picking_vals)
        try:
            picking.action_confirm()
            picking.action_assign()
        except Exception:
            pass

        self.picking_id = picking.id
        return picking

    def action_mark_qc_done(self):
        """Mark QC as performed (Day 15 QC)."""
        for rec in self:
            if not rec.qc_line_ids:
                raise UserError(_("Please add at least one Quality Check line before marking QC as done."))
            if any(not line.status for line in rec.qc_line_ids):
                raise UserError(_("Please select Pass or Fail for all Quality Check lines before marking QC as done."))
            rec.write({
                'state': 'qc_done',
                'qc_date': fields.Date.context_today(rec),
                'qc_user_id': self.env.user.id,
            })
        return True

    def action_ready_for_bottling(self):
        """Move batch to Ready for Bottling."""
        for rec in self:
            if rec.qc_status != 'pass':
                raise UserError(_("Only batches with an overall QC status of 'Pass' can proceed to Bottling."))
            rec.write({'state': 'ready_bottling'})
        return True

    def action_done(self):
        """Complete fermentation and release the tank."""
        for rec in self:
            rec.write({'state': 'done'})
            if rec.tank_id:
                rec.tank_id.write({'state': 'available', 'current_process_id': False})
        return True

    def action_cancel(self):
        for rec in self:
            rec.write({'state': 'cancel'})
            if rec.tank_id and rec.tank_id.current_process_id == rec:
                rec.tank_id.write({'state': 'available', 'current_process_id': False})
        return True

    def action_reset_draft(self):
        for rec in self:
            rec.write({'state': 'draft'})
        return True

    def action_view_picking(self):
        self.ensure_one()
        return {
            'name': _('Stock Transfer'),
            'type': 'ir.actions.act_window',
            'res_model': 'stock.picking',
            'view_mode': 'form',
            'res_id': self.picking_id.id,
        }
