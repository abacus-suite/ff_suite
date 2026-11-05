from odoo import api, fields, models, _
from odoo.exceptions import UserError


class L4eMrpSuggestWizard(models.TransientModel):
    _name = 'l4e.mrp.suggest.wizard'
    _description = 'Suggest Manufacturing Orders Review Wizard'

    company_id = fields.Many2one('res.company', string='Company', default=lambda self: self.env.company, required=True)
    line_ids = fields.One2many('l4e.mrp.suggest.line', 'wizard_id', string='Finished Goods to Produce')
    raw_material_ids = fields.One2many('l4e.mrp.suggest.raw.line', 'wizard_id', string='Raw Material Requirements')

    total_mo_count = fields.Integer(string='Total MOs', compute='_compute_totals')
    total_production_qty = fields.Float(string='Total Production Units', compute='_compute_totals')
    has_shortage = fields.Boolean(string='Has Material Shortage', compute='_compute_totals')

    @api.depends('line_ids.approved_qty', 'raw_material_ids.is_shortage')
    def _compute_totals(self):
        for wizard in self:
            valid_lines = wizard.line_ids.filtered(lambda l: l.approved_qty > 0.0)
            wizard.total_mo_count = len(valid_lines)
            wizard.total_production_qty = sum(valid_lines.mapped('approved_qty'))
            wizard.has_shortage = any(wizard.raw_material_ids.mapped('is_shortage'))

    def _compute_raw_material_lines(self):
        """Explode BOMs for all approved lines and check raw material stock availability."""
        self.ensure_one()
        self.raw_material_ids.unlink()

        raw_reqs = {} # product_id -> {'qty': float, 'uom': uom_id}

        for line in self.line_ids:
            if not line.product_id or line.approved_qty <= 0.0 or not line.bom_id:
                continue

            # Explode BOM components
            bom = line.bom_id
            factor = line.approved_qty / (bom.product_qty or 1.0)
            for bom_line in bom.bom_line_ids:
                comp = bom_line.product_id
                comp_qty = bom_line.product_qty * factor
                if comp.id not in raw_reqs:
                    raw_reqs[comp.id] = {
                        'product_id': comp.id,
                        'uom_id': bom_line.product_uom_id.id,
                        'required_qty': comp_qty,
                    }
                else:
                    raw_reqs[comp.id]['required_qty'] += comp_qty

        raw_vals = []
        Product = self.env['product.product']
        for pid, data in raw_reqs.items():
            comp_prod = Product.browse(pid)
            avail = comp_prod.free_qty if hasattr(comp_prod, 'free_qty') else (comp_prod.qty_available or 0.0)
            req = data['required_qty']
            shortage = max(0.0, req - avail)
            raw_vals.append((0, 0, {
                'wizard_id': self.id,
                'product_id': pid,
                'uom_id': data['uom_id'],
                'required_qty': req,
                'on_hand_qty': avail,
                'shortage_qty': shortage,
                'is_shortage': shortage > 0.0,
            }))

        if raw_vals:
            self.write({'raw_material_ids': raw_vals})

    def action_recalculate_materials(self):
        """Button to recalculate raw material requirements after editing quantities."""
        self._compute_raw_material_lines()
        return {
            'type': 'ir.actions.act_window',
            'res_model': self._name,
            'res_id': self.id,
            'view_mode': 'form',
            'target': 'new',
        }

    def action_generate_mos(self):
        """Create draft Manufacturing Orders for approved lines."""
        self.ensure_one()
        valid_lines = self.line_ids.filtered(lambda l: l.approved_qty > 0.0 and l.bom_id)

        if not valid_lines:
            raise UserError(_('Please specify an approved quantity > 0 and ensure products have an active BOM.'))

        today_str = fields.Date.today().strftime('%d-%b-%Y')
        created_mos = self.env['mrp.production']

        for line in valid_lines:
            mo = self.env['mrp.production'].create({
                'product_id': line.product_id.id,
                'product_qty': line.approved_qty,
                'bom_id': line.bom_id.id,
                'origin': _('Manager Plan: %(date)s (Sales: %(lws)s, Deliv: %(nwd)s)',
                            date=today_str,
                            lws=int(line.last_week_sales),
                            nwd=int(line.next_week_deliveries)),
                'company_id': self.company_id.id,
            })
            created_mos |= mo

        # Return action to view created MOs
        action = self.env['ir.actions.act_window']._for_xml_id('mrp.mrp_production_action')
        if len(created_mos) == 1:
            action['views'] = [(self.env.ref('mrp.mrp_production_form_view').id, 'form')]
            action['res_id'] = created_mos.id
        else:
            action['domain'] = [('id', 'in', created_mos.ids)]
            action['views'] = [(self.env.ref('mrp.mrp_production_tree_view').id, 'list'), (self.env.ref('mrp.mrp_production_form_view').id, 'form')]

        return action


class L4eMrpSuggestLine(models.TransientModel):
    _name = 'l4e.mrp.suggest.line'
    _description = 'Finished Good Suggestion Line'

    wizard_id = fields.Many2one('l4e.mrp.suggest.wizard', ondelete='cascade', required=True)
    product_id = fields.Many2one('product.product', string='Finished Product', required=True)
    uom_id = fields.Many2one(related='product_id.uom_id', string='Unit')
    bom_id = fields.Many2one('mrp.bom', string='Bill of Materials', compute='_compute_bom_id', store=True, readonly=False)

    last_week_sales = fields.Float(string='Last Week Sales', digits='Product Unit of Measure', readonly=True)
    next_week_deliveries = fields.Float(string='Next Week Deliveries', digits='Product Unit of Measure', readonly=True)
    qty_available = fields.Float(string='Current Stock', digits='Product Unit of Measure', readonly=True)
    suggested_qty = fields.Float(string='System Suggested', digits='Product Unit of Measure', readonly=True)
    approved_qty = fields.Float(string='Approved Qty to Produce', digits='Product Unit of Measure', required=True)
    notes = fields.Char(string='Notes / Instructions')

    @api.depends('product_id')
    def _compute_bom_id(self):
        Bom = self.env['mrp.bom']
        for line in self:
            if not line.product_id:
                line.bom_id = False
                continue
            bom = Bom._bom_find(line.product_id, company_id=line.wizard_id.company_id.id)[line.product_id]
            line.bom_id = bom.id if bom else False

    @api.onchange('product_id')
    def _onchange_product_id(self):
        if self.product_id and not self.suggested_qty:
            avail = self.product_id.free_qty if hasattr(self.product_id, 'free_qty') else (self.product_id.qty_available or 0.0)
            self.qty_available = avail


class L4eMrpSuggestRawLine(models.TransientModel):
    _name = 'l4e.mrp.suggest.raw.line'
    _description = 'Raw Material Requirement Line'

    wizard_id = fields.Many2one('l4e.mrp.suggest.wizard', ondelete='cascade', required=True)
    product_id = fields.Many2one('product.product', string='Raw Material Component', required=True)
    uom_id = fields.Many2one('uom.uom', string='Unit')
    required_qty = fields.Float(string='Required Quantity', digits='Product Unit of Measure')
    on_hand_qty = fields.Float(string='Available Stock', digits='Product Unit of Measure')
    shortage_qty = fields.Float(string='Shortage / Deficit', digits='Product Unit of Measure')
    is_shortage = fields.Boolean(string='Shortage Alert', default=False)
