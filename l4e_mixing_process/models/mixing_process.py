# -*- coding: utf-8 -*-
from odoo import models, fields, api, _
from odoo.exceptions import UserError


class MixingProcess(models.Model):
    _name = 'mixing.process'
    _description = 'Mixing Process & Quality Verification'
    _inherit = ['mail.thread', 'mail.activity.mixin']
    _order = 'date desc, id desc'

    name = fields.Char(
        string='Mixing Process No',
        required=True,
        copy=False,
        readonly=True,
        index=True,
        default=lambda self: _('New'),
        tracking=True,
    )
    mrp_id = fields.Many2one(
        'mrp.production',
        string='Manufacturing Order',
        readonly=True,
        tracking=True,
        index=True,
        help="Manufacturing Order from which this mixing process originated.",
    )
    product_id = fields.Many2one(
        'product.product',
        string='Product',
        required=True,
        tracking=True,
        index=True,
        help="Manufactured product being mixed.",
    )
    quantity = fields.Float(
        string='Quantity',
        digits='Product Unit of Measure',
        required=True,
        default=0.0,
        tracking=True,
        help="Quantity produced from the MO to be mixed.",
    )
    uom_id = fields.Many2one(
        'uom.uom',
        string='Unit of Measure',
        related='product_id.uom_id',
        readonly=True,
    )
    date = fields.Date(
        string='Date',
        default=fields.Date.context_today,
        required=True,
        tracking=True,
    )
    location_id = fields.Many2one(
        'stock.location',
        string='Source Location',
        default=lambda self: self._default_source_location(),
        required=True,
        help="Location where the mixed goods currently reside (Mixing Area).",
    )
    location_dest_id = fields.Many2one(
        'stock.location',
        string='Destination Location',
        default=lambda self: self._default_dest_location(),
        required=True,
        help="Destination location for packing (Packing).",
    )
    state = fields.Selection(
        [
            ('draft', 'Draft'),
            ('first_qc', '1st QC Verified (In Mixing)'),
            ('second_qc', '2nd QC Verified (Mixing Done)'),
            ('done', 'Done (Transferred to Packing)'),
            ('cancel', 'Cancelled'),
        ],
        string='Status',
        default='draft',
        required=True,
        tracking=True,
        index=True,
    )
    first_qc_line_ids = fields.One2many(
        'mixing.qc.line',
        'process_first_id',
        string='1st QC Check Lines',
        copy=True,
    )
    second_qc_line_ids = fields.One2many(
        'mixing.qc.line',
        'process_second_id',
        string='2nd QC Check Lines',
        copy=True,
    )
    first_qc_status = fields.Selection(
        [
            ('pass', 'Pass'),
            ('fail', 'Fail'),
        ],
        string='1st QC Status',
        compute='_compute_first_qc_status',
        store=True,
        readonly=False,
        tracking=True,
    )
    second_qc_status = fields.Selection(
        [
            ('pass', 'Pass'),
            ('fail', 'Fail'),
        ],
        string='2nd QC Status',
        compute='_compute_second_qc_status',
        store=True,
        readonly=False,
        tracking=True,
    )
    first_qc_date = fields.Date(
        string='1st QC Date',
        tracking=True,
    )
    first_qc_user_id = fields.Many2one(
        'res.users',
        string='1st QC Verified By',
        tracking=True,
    )
    second_qc_date = fields.Date(
        string='2nd QC Date',
        tracking=True,
    )
    second_qc_user_id = fields.Many2one(
        'res.users',
        string='2nd QC Verified By',
        tracking=True,
    )
    picking_id = fields.Many2one(
        'stock.picking',
        string='Internal Transfer (to Packing)',
        readonly=True,
        copy=False,
        tracking=True,
        help="Draft internal transfer created to move finished mixed product to the Packing location.",
    )
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
        mixing_loc = self.env.ref('l4e_mixing_process.location_mixing_area', raise_if_not_found=False)
        if mixing_loc:
            return mixing_loc
        return self.env['stock.location'].search([('name', '=', 'Mixing Area'), ('usage', '=', 'internal')], limit=1)

    def _default_dest_location(self):
        packing_loc = self.env.ref('l4e_product_location.location_packing', raise_if_not_found=False)
        if packing_loc:
            return packing_loc
        return self.env['stock.location'].search([('name', '=', 'Packing'), ('usage', '=', 'internal')], limit=1)

    @api.depends('first_qc_line_ids.status')
    def _compute_first_qc_status(self):
        for rec in self:
            if not rec.first_qc_line_ids:
                rec.first_qc_status = False
                continue
            statuses = [line.status for line in rec.first_qc_line_ids if line.status]
            if any(st == 'fail' for st in statuses):
                rec.first_qc_status = 'fail'
            elif statuses and all(st == 'pass' for st in statuses):
                rec.first_qc_status = 'pass'
            else:
                rec.first_qc_status = False

    @api.depends('second_qc_line_ids.status')
    def _compute_second_qc_status(self):
        for rec in self:
            if not rec.second_qc_line_ids:
                rec.second_qc_status = False
                continue
            statuses = [line.status for line in rec.second_qc_line_ids if line.status]
            if any(st == 'fail' for st in statuses):
                rec.second_qc_status = 'fail'
            elif statuses and all(st == 'pass' for st in statuses):
                rec.second_qc_status = 'pass'
            else:
                rec.second_qc_status = False

    @api.model_create_multi
    def create(self, vals_list):
        for vals in vals_list:
            if not vals.get('name') or vals.get('name') == _('New'):
                vals['name'] = self.env['ir.sequence'].next_by_code('mixing.process') or _('New')
        return super().create(vals_list)

    def action_confirm_first_qc(self):
        """Verify 1st QC check (Pre-Mixing) and advance stage to In Mixing."""
        for rec in self:
            if not rec.first_qc_line_ids:
                raise UserError(_("Please add at least one line under the 1st QC Check tab before verifying."))
            if rec.first_qc_status != 'pass':
                raise UserError(_("1st QC Check has not passed. Only batches with Pass status can proceed to mixing."))
            rec.write({
                'state': 'first_qc',
                'first_qc_date': fields.Date.context_today(rec),
                'first_qc_user_id': self.env.user.id,
            })
        return True

    def action_confirm_second_qc(self):
        """Verify 2nd QC check (Post-Mixing) and advance stage to Mixing Done."""
        for rec in self:
            if not rec.second_qc_line_ids:
                raise UserError(_("Please add at least one line under the 2nd QC Check tab before verifying."))
            if rec.second_qc_status != 'pass':
                raise UserError(_("2nd QC Check has not passed. Only batches with Pass status can proceed."))
            rec.write({
                'state': 'second_qc',
                'second_qc_date': fields.Date.context_today(rec),
                'second_qc_user_id': self.env.user.id,
            })
        return True

    def action_done(self):
        """
        Mark mixing as Done:
        Creates a draft internal transfer from Mixing Area to Packing location.
        """
        for rec in self:
            if rec.state != 'second_qc':
                raise UserError(_("You can only complete the process after the 2nd QC check is verified."))
            rec._create_packing_transfer()
            rec.write({'state': 'done'})
        return True

    def _create_packing_transfer(self):
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

        move_fields = self.env['stock.move']._fields
        move_val = {
            'product_id': self.product_id.id,
            'product_uom_qty': self.quantity,
            'location_id': source_loc.id if source_loc else False,
            'location_dest_id': dest_loc.id if dest_loc else False,
        }
        if 'product_uom' in move_fields:
            move_val['product_uom'] = self.uom_id.id or self.product_id.uom_id.id
        elif 'product_uom_id' in move_fields:
            move_val['product_uom_id'] = self.uom_id.id or self.product_id.uom_id.id

        if 'description_picking' in move_fields:
            move_val['description_picking'] = f"Mixing to Packing: {self.name}"
        elif 'name' in move_fields:
            move_val['name'] = f"Mixing to Packing: {self.name}"

        picking_vals = {
            'picking_type_id': picking_type.id if picking_type else False,
            'location_id': source_loc.id if source_loc else False,
            'location_dest_id': dest_loc.id if dest_loc else False,
            'origin': f"{self.name} - Transfer to Packing",
            'company_id': self.company_id.id,
            'move_ids': [(0, 0, move_val)],
        }
        # Create picking in draft stage (without calling action_confirm)
        picking = self.env['stock.picking'].create(picking_vals)
        self.picking_id = picking.id
        return picking

    def action_cancel(self):
        for rec in self:
            rec.write({'state': 'cancel'})
        return True

    def action_reset_draft(self):
        for rec in self:
            rec.write({'state': 'draft'})
        return True

    def action_view_picking(self):
        self.ensure_one()
        return {
            'name': _('Internal Transfer to Packing'),
            'type': 'ir.actions.act_window',
            'res_model': 'stock.picking',
            'view_mode': 'form',
            'res_id': self.picking_id.id,
        }
