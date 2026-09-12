"""Turn a pile of outlet demands into one quotation per distributor.

The office selects demands - a route, a day, a product shortage - and this
merges them: same product across ten outlets becomes one line with the total
quantity, priced at PTS, on a quotation addressed to the distributor who serves
those outlets. Each demand keeps the link, so the officer sees what happened.
"""
from odoo import api, fields, models
from odoo.exceptions import UserError


class FfDemandQuotation(models.TransientModel):
    _name = 'ff.demand.quotation'
    _description = 'Create Distributor Quotation'

    demand_ids = fields.Many2many('ff.demand', string='Demands', required=True)
    distributor_id = fields.Many2one('res.partner', string='Distributor',
                                     domain=[('ff_is_distributor', '=', True)],
                                     help='Leave empty to create one quotation per distributor.')
    line_ids = fields.One2many('ff.demand.quotation.line', 'wizard_id', string='Consolidated Products')
    confirm_orders = fields.Boolean(string='Confirm the quotations', default=False,
                                    help='Create them as confirmed sales orders instead of drafts.')
    outlet_count = fields.Integer(compute='_compute_summary')
    distributor_count = fields.Integer(compute='_compute_summary')
    missing_distributor = fields.Integer(compute='_compute_summary')

    @api.depends('demand_ids')
    def _compute_summary(self):
        for wizard in self:
            demands = wizard.demand_ids
            wizard.outlet_count = len(demands.mapped('partner_id'))
            wizard.distributor_count = len(demands.mapped('distributor_id'))
            wizard.missing_distributor = len(demands.filtered(lambda d: not d.distributor_id))

    @api.model
    def default_get(self, fields_list):
        values = super().default_get(fields_list)
        demands = self.env['ff.demand'].browse(self.env.context.get('active_ids', []))
        demands = demands.filtered(lambda d: d.state not in ('cancelled', 'supplied'))
        if not demands:
            raise UserError(self.env._('Select demands that are still waiting to be quoted.'))
        values['demand_ids'] = [(6, 0, demands.ids)]
        values['line_ids'] = [(0, 0, line) for line in self._consolidate(demands)]
        return values

    def _consolidate(self, demands):
        """One row per product per distributor, carrying what is still pending."""
        rows = {}
        for line in demands.mapped('line_ids'):
            pending = line.pending_quantity
            if pending <= 0:
                continue
            key = (line.demand_id.distributor_id.id, line.product_id.id)
            row = rows.setdefault(key, {
                'distributor_id': line.demand_id.distributor_id.id,
                'product_id': line.product_id.id,
                'quantity': 0.0,
                'outlets': 0,
                'price_unit': line.product_id.ff_distributor_price(),
            })
            row['quantity'] += pending
            row['outlets'] += 1
        return sorted(rows.values(), key=lambda row: (row['distributor_id'] or 0, row['product_id']))

    def action_create(self):
        """Create the quotations and tie the demands to them."""
        self.ensure_one()
        rows = self.line_ids.filtered(lambda line: line.quantity > 0)
        if not rows:
            raise UserError(self.env._('Nothing left to quote: every line is zero.'))
        missing = rows.filtered(lambda line: not (line.distributor_id or self.distributor_id))
        if missing:
            raise UserError(self.env._(
                'These products have no distributor: %s. Set one on the outlet, on the route, '
                'or choose a distributor above.',
                ', '.join(missing.mapped('product_id.display_name')[:5])))

        Order = self.env['sale.order']
        orders = Order.browse()
        for distributor, lines in self._by_distributor(rows).items():
            order = Order.create({
                'partner_id': distributor.id,
                'origin': ', '.join(self.demand_ids.mapped('name')[:8]),
                'order_line': [(0, 0, {
                    'product_id': line.product_id.id,
                    'product_uom_qty': line.quantity,
                    'price_unit': line.price_unit,
                }) for line in lines],
            })
            orders |= order
            self._settle(order, lines, distributor)
        if self.confirm_orders:
            orders.action_confirm()
        self.demand_ids._ff_refresh_state()
        return {
            'type': 'ir.actions.act_window',
            'name': self.env._('Distributor Quotations'),
            'res_model': 'sale.order',
            'domain': [('id', 'in', orders.ids)],
            'view_mode': 'list,form',
        }

    def _by_distributor(self, rows):
        grouped = {}
        for row in rows:
            distributor = row.distributor_id or self.distributor_id
            grouped.setdefault(distributor, self.env['ff.demand.quotation.line'])
            grouped[distributor] |= row
        return grouped

    def _settle(self, order, rows, distributor):
        """Write back how much of each demand this quotation covers."""
        for row in rows:
            remaining = row.quantity
            demand_lines = self.demand_ids.mapped('line_ids').filtered(
                lambda line, row=row, distributor=distributor:
                line.product_id == row.product_id
                and line.pending_quantity > 0
                and (line.demand_id.distributor_id == distributor or not line.demand_id.distributor_id))
            for line in demand_lines:
                if remaining <= 0:
                    break
                taken = min(line.pending_quantity, remaining)
                line.quoted_quantity += taken
                remaining -= taken
                if not line.demand_id.distributor_id:
                    line.demand_id.distributor_id = distributor.id
                line.demand_id.order_ids = [(4, order.id)]


class FfDemandQuotationLine(models.TransientModel):
    _name = 'ff.demand.quotation.line'
    _description = 'Consolidated Demand Line'
    _order = 'distributor_id, product_id'

    wizard_id = fields.Many2one('ff.demand.quotation', required=True, ondelete='cascade')
    distributor_id = fields.Many2one('res.partner', string='Distributor')
    product_id = fields.Many2one('product.product', required=True)
    quantity = fields.Float(string='Quantity', required=True)
    outlets = fields.Integer(string='Outlets', readonly=True)
    price_unit = fields.Monetary(string='PTS')
    currency_id = fields.Many2one('res.currency', default=lambda self: self.env.company.currency_id)
    subtotal = fields.Monetary(compute='_compute_subtotal')

    @api.depends('quantity', 'price_unit')
    def _compute_subtotal(self):
        for line in self:
            line.subtotal = line.quantity * line.price_unit
