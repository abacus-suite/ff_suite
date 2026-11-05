from datetime import timedelta
from odoo import api, fields, models, _
from odoo.exceptions import UserError


class L4eMrpPlan(models.Model):
    _name = 'l4e.mrp.plan'
    _description = 'Weekly Production Demand Plan'
    _order = 'suggested_qty desc, product_id asc'

    product_id = fields.Many2one('product.product', string='Product', required=True, index=True, ondelete='cascade')
    default_code = fields.Char(related='product_id.default_code', string='Internal Reference', store=True)
    categ_id = fields.Many2one(related='product_id.categ_id', string='Product Category', store=True)
    uom_id = fields.Many2one(related='product_id.uom_id', string='Unit of Measure')
    bom_id = fields.Many2one('mrp.bom', string='Active BOM', compute='_compute_bom_id', store=True)
    has_bom = fields.Boolean(string='Has BOM', compute='_compute_bom_id', store=True)

    last_week_sales = fields.Float(string='Last Week Sales', digits='Product Unit of Measure')
    next_week_deliveries = fields.Float(string='Next Week Deliveries', digits='Product Unit of Measure')
    qty_available = fields.Float(string='Available Stock', digits='Product Unit of Measure')
    suggested_qty = fields.Float(string='Suggested MO Qty', compute='_compute_suggested_qty', store=True,
                                 digits='Product Unit of Measure')
    needs_mo = fields.Boolean(string='Needs MO', compute='_compute_suggested_qty', store=True, index=True)

    company_id = fields.Many2one('res.company', string='Company', default=lambda self: self.env.company, required=True)
    date_calculated = fields.Datetime(string='Calculated On', default=fields.Datetime.now)

    @api.depends('product_id')
    def _compute_bom_id(self):
        Bom = self.env['mrp.bom']
        for record in self:
            if not record.product_id:
                record.bom_id = False
                record.has_bom = False
                continue
            bom = Bom._bom_find(record.product_id, company_id=record.company_id.id)[record.product_id]
            record.bom_id = bom.id if bom else False
            record.has_bom = bool(bom)

    @api.depends('last_week_sales', 'next_week_deliveries', 'qty_available')
    def _compute_suggested_qty(self):
        for record in self:
            total_demand = (record.last_week_sales or 0.0) + (record.next_week_deliveries or 0.0)
            avail = record.qty_available or 0.0
            gap = total_demand - avail
            record.suggested_qty = max(0.0, gap)
            record.needs_mo = record.suggested_qty > 0.0

    @api.model
    def action_refresh_plan(self):
        """Recalculate last week sales, next week deliveries, and available stock for all active products."""
        today = fields.Date.context_today(self)
        last_week_start = today - timedelta(days=7)
        next_week_end = today + timedelta(days=7)
        company_id = self.env.company.id

        # 1. Eligible products: manufactured products (having BOM) or storable goods
        boms = self.env['mrp.bom'].search([('company_id', 'in', (False, company_id)), ('active', '=', True)])
        bom_product_tmpl_ids = boms.mapped('product_tmpl_id').ids
        products = self.env['product.product'].search([
            ('active', '=', True),
            ('type', '=', 'consu'), # In Odoo 19, storable is tracked under type
            '|',
            ('product_tmpl_id', 'in', bom_product_tmpl_ids),
            ('bom_ids', '!=', False)
        ])

        if not products:
            # Fallback to any active products if BOM filter is broad
            products = self.env['product.product'].search([('active', '=', True)], limit=500)

        # 2. Query Last Week Sales (delivered or confirmed)
        sales_data = {}
        so_lines = self.env['sale.order.line'].search([
            ('company_id', '=', company_id),
            ('state', 'in', ('sale', 'done')),
            ('order_id.date_order', '>=', fields.Datetime.to_datetime(last_week_start)),
            ('order_id.date_order', '<=', fields.Datetime.to_datetime(today)),
            ('product_id', 'in', products.ids),
        ])
        for line in so_lines:
            sales_data[line.product_id.id] = sales_data.get(line.product_id.id, 0.0) + line.product_uom_qty

        # 3. Query Next Week Deliveries (outgoing moves scheduled in next 7 days)
        delivery_data = {}
        moves = self.env['stock.move'].search([
            ('company_id', '=', company_id),
            ('state', 'in', ('confirmed', 'partially_available', 'assigned', 'waiting')),
            ('picking_id.picking_type_code', '=', 'outgoing'),
            ('date', '>=', fields.Datetime.to_datetime(today)),
            ('date', '<=', fields.Datetime.to_datetime(next_week_end)),
            ('product_id', 'in', products.ids),
        ])
        for move in moves:
            delivery_data[move.product_id.id] = delivery_data.get(move.product_id.id, 0.0) + move.product_uom_qty

        # 4. Clean up old plan and recreate entries
        self.search([('company_id', '=', company_id)]).unlink()

        vals_list = []
        for prod in products:
            lws = sales_data.get(prod.id, 0.0)
            nwd = delivery_data.get(prod.id, 0.0)
            avail = prod.free_qty if hasattr(prod, 'free_qty') else (prod.qty_available or 0.0)

            # Keep items with non-zero sales, deliveries, or available stock
            if lws > 0.0 or nwd > 0.0 or avail > 0.0:
                vals_list.append({
                    'product_id': prod.id,
                    'last_week_sales': lws,
                    'next_week_deliveries': nwd,
                    'qty_available': avail,
                    'company_id': company_id,
                    'date_calculated': fields.Datetime.now(),
                })

        if vals_list:
            self.create(vals_list)

        return True

    def action_open_suggest_wizard(self):
        """Open the interactive Suggest MO review wizard."""
        # Refresh first to ensure fresh data
        self.action_refresh_plan()

        company_id = self.env.company.id
        plans_needing_mo = self.search([
            ('company_id', '=', company_id),
            ('needs_mo', '=', True),
        ])

        wizard = self.env['l4e.mrp.suggest.wizard'].create({
            'company_id': company_id,
        })

        lines = []
        for plan in plans_needing_mo:
            lines.append((0, 0, {
                'wizard_id': wizard.id,
                'product_id': plan.product_id.id,
                'bom_id': plan.bom_id.id if plan.bom_id else False,
                'last_week_sales': plan.last_week_sales,
                'next_week_deliveries': plan.next_week_deliveries,
                'qty_available': plan.qty_available,
                'suggested_qty': plan.suggested_qty,
                'approved_qty': plan.suggested_qty,
            }))

        if lines:
            wizard.write({'line_ids': lines})
            wizard._compute_raw_material_lines()

        return {
            'type': 'ir.actions.act_window',
            'name': _('Suggest Manufacturing Orders (Editable Review)'),
            'res_model': 'l4e.mrp.suggest.wizard',
            'view_mode': 'form',
            'res_id': wizard.id,
            'target': 'new',
            'context': {'default_company_id': company_id},
        }

    @api.model
    def _cron_generate_weekly_draft_mos(self):
        """Called every Friday by Scheduled Action to generate draft Manufacturing Orders."""
        self.action_refresh_plan()

        company_id = self.env.company.id
        plans = self.search([
            ('company_id', '=', company_id),
            ('needs_mo', '=', True),
            ('bom_id', '!=', False),
        ])

        today_str = fields.Date.today().strftime('%d-%b-%Y')
        created_mos = self.env['mrp.production']

        for plan in plans:
            if plan.suggested_qty <= 0.0 or not plan.bom_id:
                continue

            mo = self.env['mrp.production'].create({
                'product_id': plan.product_id.id,
                'product_qty': plan.suggested_qty,
                'bom_id': plan.bom_id.id,
                'origin': _('Auto-Plan: Friday %(date)s (Sales: %(lws)s, Deliv: %(nwd)s)',
                            date=today_str,
                            lws=int(plan.last_week_sales),
                            nwd=int(plan.next_week_deliveries)),
                'company_id': company_id,
            })
            created_mos |= mo

        return created_mos.ids
