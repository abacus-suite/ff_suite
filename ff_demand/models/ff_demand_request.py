"""What goes to a distributor to be approved, and what they deliver against it.

Outlet demands are not quoted on a sale order. The demands raised for one
distributor are sent to them together as a request: they approve it (all of it,
or less than was asked), then record what they actually delivered to each outlet.
The outlet is billed only for what was delivered.
"""
from odoo import api, fields, models
from odoo.exceptions import UserError


class FfDemandDeliveryStatus(models.Model):
    _name = 'ff.demand.delivery.status'
    _description = 'Demand Delivery Status'
    _order = 'sequence, id'

    name = fields.Char(required=True, translate=True)
    code = fields.Selection([
        ('progress', 'In Progress'), ('partial', 'Partially Delivered'), ('full', 'Fully Delivered'),
    ], required=True, index=True, help='How the demand reads this status: nothing delivered yet, '
                                       'some delivered, or everything approved delivered.')
    sequence = fields.Integer(default=10)
    color = fields.Integer(default=0)
    active = fields.Boolean(default=True)

    _code_uniq = models.Constraint('UNIQUE(code)', 'There is already a status for that stage.')

    @api.model
    def ff_get(self, code):
        return self.sudo().with_context(active_test=False).search([('code', '=', code)], limit=1)


class FfDemandRequest(models.Model):
    _name = 'ff.demand.request'
    _description = 'Distributor Demand Request'
    _inherit = ['mail.thread']
    _order = 'date_order desc, id desc'

    name = fields.Char(default=lambda self: self.env._('New'), copy=False, readonly=True)
    # Named like the sale order's fields so the one approval page serves both.
    partner_id = fields.Many2one('res.partner', string='Distributor', required=True, index=True,
                                 domain=[('ff_is_distributor', '=', True)], tracking=True)
    ff_employee_id = fields.Many2one('hr.employee', string='Raised By', index=True, ondelete='set null')
    date_order = fields.Datetime(string='Sent On', default=fields.Datetime.now, index=True)
    company_id = fields.Many2one('res.company', required=True, default=lambda self: self.env.company)
    currency_id = fields.Many2one(related='company_id.currency_id')
    demand_ids = fields.One2many('ff.demand', 'request_id', string='Outlet Demands')
    demand_count = fields.Integer(compute='_compute_totals', store=True)
    origin = fields.Char(compute='_compute_totals', store=True, string='Demands')
    amount_total = fields.Monetary(compute='_compute_totals', store=True, string='Demand Value')
    approved_total = fields.Monetary(compute='_compute_totals', store=True, string='Approved Value')
    delivered_total = fields.Monetary(compute='_compute_totals', store=True, string='Delivered Value')
    state = fields.Selection([
        ('sent', 'Waiting for Distributor'), ('approved', 'Approved'),
        ('rejected', 'Rejected'), ('done', 'Fully Delivered'),
    ], default='sent', required=True, index=True, tracking=True)
    distributor_confirmed_date = fields.Datetime(string='Approved On', readonly=True, copy=False)
    distributor_rejected_date = fields.Datetime(string='Rejected On', readonly=True, copy=False)
    distributor_note = fields.Text(string='Distributor Note', readonly=True, copy=False)

    @api.depends('demand_ids.amount_total', 'demand_ids.line_ids.approved_quantity',
                 'demand_ids.line_ids.delivered_quantity', 'demand_ids.state')
    def _compute_totals(self):
        for request in self:
            demands = request.demand_ids
            request.demand_count = len(demands)
            request.origin = ', '.join(demands.mapped('name')[:8])
            request.amount_total = sum(demands.mapped('amount_total'))
            approved = delivered = 0.0
            for line in demands.mapped('line_ids'):
                if not line.quantity:
                    continue
                unit = line.price_total / line.quantity
                approved += unit * line.approved_quantity
                delivered += unit * line.delivered_quantity
            request.approved_total = approved
            request.delivered_total = delivered

    @api.model_create_multi
    def create(self, vals_list):
        for vals in vals_list:
            if vals.get('name', self.env._('New')) == self.env._('New'):
                vals['name'] = self.env['ir.sequence'].sudo().next_by_code('ff.demand.request') or '/'
        return super().create(vals_list)

    # ------------------------------------------------------------------
    # What the distributor is shown
    # ------------------------------------------------------------------
    def ff_lines(self):
        """The products asked for, added up across the outlets: one row per product, free goods apart."""
        self.ensure_one()
        rows = {}
        for line in self.demand_ids.mapped('line_ids'):
            free = bool(getattr(line, 'is_foc', False))
            key = (line.product_id.id, free)
            row = rows.setdefault(key, {
                'id': line.product_id.id * 2 + (1 if free else 0),
                'product': line.product_id, 'free': free, 'price': line.price_unit, 'tax': line.tax_percent,
                'uom': line.uom_id.name or '',
                'demanded': 0.0, 'approved': 0.0, 'delivered': 0.0, 'subtotal': 0.0,
            })
            row['demanded'] += line.quantity
            row['approved'] += line.approved_quantity
            row['delivered'] += line.delivered_quantity
            row['subtotal'] += line.subtotal
        return sorted(rows.values(), key=lambda r: (r['free'], r['product'].display_name or ''))

    # ------------------------------------------------------------------
    # The distributor's decision
    # ------------------------------------------------------------------
    def ff_approve(self, quantities, note=None):
        """Approve, supplying ``quantities`` ({row id: units}); a product left out is supplied in full.

        What a product's total comes to is shared out to the outlets in the order they asked, so the
        earlier demand is met first and nobody is promised more than they asked for.
        """
        self.ensure_one()
        if self.state != 'sent':
            raise UserError(self.env._('%s has already been answered.', self.name))
        rows = {row['id']: row for row in self.ff_lines()}
        if not any((quantities.get(rid, row['demanded']) or 0) > 0 for rid, row in rows.items()):
            raise UserError(self.env._('Supply at least one unit, or reject the request.'))
        for rid, row in rows.items():
            try:
                supplied = float(quantities.get(rid, row['demanded']) or 0)
            except (TypeError, ValueError):
                supplied = row['demanded']
            supplied = min(max(supplied, 0.0), row['demanded'])
            lines = self.demand_ids.mapped('line_ids').filtered(
                lambda l, row=row: l.product_id == row['product'] and bool(getattr(l, 'is_foc', False)) == row['free']
            ).sorted(lambda l: (l.demand_id.date, l.id))
            for line in lines:
                give = min(line.quantity, supplied)
                line.sudo().approved_quantity = give
                supplied -= give
        now = fields.Datetime.now()
        for demand in self.demand_ids:
            if sum(demand.line_ids.mapped('approved_quantity')) > 0:
                demand.sudo().write({'state': 'approved', 'approved_on': now})
                demand.message_post(body=self.env._('Approved by %s.', self.partner_id.display_name))
                if 'ff.notification' in self.env and demand.employee_id:
                    self.env['ff.notification'].sudo().ff_push(
                        title=self.env._('Demand Approved'),
                        body=self.env._('Demand %(name)s for %(outlet)s was approved by distributor %(dist)s.',
                                        name=demand.name, outlet=demand.partner_id.name, dist=self.partner_id.name),
                        kind='decision',
                        employee=demand.employee_id,
                        record=demand,
                    )
            else:
                demand.sudo().write({'state': 'rejected', 'reject_note': self.env._('The distributor could not supply it.')})
                if 'ff.notification' in self.env and demand.employee_id:
                    self.env['ff.notification'].sudo().ff_push(
                        title=self.env._('Demand Rejected'),
                        body=self.env._('Demand %(name)s for %(outlet)s was rejected by distributor %(dist)s.',
                                        name=demand.name, outlet=demand.partner_id.name, dist=self.partner_id.name),
                        kind='decision',
                        employee=demand.employee_id,
                        record=demand,
                    )
        self.sudo().write({'state': 'approved', 'distributor_confirmed_date': now,
                           'distributor_note': (note or '').strip() or False})
        self.demand_ids._ff_sync_delivery()
        return True

    def ff_reject(self, note=None):
        self.ensure_one()
        if self.state != 'sent':
            raise UserError(self.env._('%s has already been answered.', self.name))
        now = fields.Datetime.now()
        reason = (note or '').strip()
        self.demand_ids.sudo().write({'state': 'rejected', 'reject_note': reason or False})
        for demand in self.demand_ids:
            demand.message_post(body=self.env._('Rejected by %(who)s. %(why)s', who=self.partner_id.display_name,
                                                why=reason))
            if 'ff.notification' in self.env and demand.employee_id:
                self.env['ff.notification'].sudo().ff_push(
                    title=self.env._('Demand Rejected'),
                    body=self.env._('Demand %(name)s for %(outlet)s was rejected by distributor %(dist)s.%(note)s',
                                    name=demand.name, outlet=demand.partner_id.name, dist=self.partner_id.name,
                                    note=(': ' + reason) if reason else ''),
                    kind='decision',
                    employee=demand.employee_id,
                    record=demand,
                )
        self.sudo().write({'state': 'rejected', 'distributor_rejected_date': now,
                           'distributor_note': reason or False})
        return True

    def ff_deliveries(self):
        """Per outlet: what is approved, what has gone, what is left."""
        self.ensure_one()
        rows = []
        for demand in self.demand_ids.filtered(lambda d: d.state in ('approved', 'supplied')):
            lines = [{
                'id': line.id, 'name': line.product_id.display_name, 'uom': line.uom_id.name or '',
                'free': bool(getattr(line, 'is_foc', False)),
                'approved': line.approved_quantity, 'delivered': line.delivered_quantity,
                'left': max(line.approved_quantity - line.delivered_quantity, 0.0),
            } for line in demand.line_ids if line.approved_quantity > 0]
            rows.append({
                'demand': demand, 'outlet': demand.partner_id, 'lines': lines,
                'status': demand.delivery_status_id.name or '',
                'history': demand.delivery_ids.sorted('id', reverse=True),
                'open': any(l['left'] > 0 for l in lines),
            })
        return rows

    def _ff_sync_state(self):
        for request in self.filtered(lambda r: r.state in ('approved', 'done')):
            live = request.demand_ids.filtered(lambda d: d.state in ('approved', 'supplied'))
            request.state = 'done' if live and all(d.state == 'supplied' for d in live) else 'approved'

    def _ff_sent(self):
        """A hook for whatever tells the distributor (a portal link, an e-mail)."""
        return True

    def action_open_demands(self):
        self.ensure_one()
        return {
            'type': 'ir.actions.act_window', 'name': self.env._('Outlet Demands'), 'res_model': 'ff.demand',
            'domain': [('id', 'in', self.demand_ids.ids)], 'view_mode': 'list,form',
        }


class FfDemandDelivery(models.Model):
    _name = 'ff.demand.delivery'
    _description = 'Delivery Against a Demand'
    _inherit = ['mail.thread']
    _order = 'date desc, id desc'

    name = fields.Char(default=lambda self: self.env._('New'), copy=False, readonly=True)
    demand_id = fields.Many2one('ff.demand', required=True, index=True, ondelete='cascade')
    partner_id = fields.Many2one(related='demand_id.partner_id', store=True, string='Outlet')
    distributor_id = fields.Many2one(related='demand_id.distributor_id', store=True, index=True)
    date = fields.Datetime(default=fields.Datetime.now, required=True, index=True)
    note = fields.Char()
    entered_by = fields.Char(string='Entered By', help='Who recorded it: the distributor in the portal, or a user in Odoo.')
    line_ids = fields.One2many('ff.demand.delivery.line', 'delivery_id', string='Delivered')
    company_id = fields.Many2one(related='demand_id.company_id', store=True)
    currency_id = fields.Many2one(related='demand_id.currency_id')
    amount = fields.Monetary(compute='_compute_amount', store=True, string='Delivered Value',
                             help='What the outlet is billed for this delivery, taxes included.')

    @api.depends('line_ids.amount')
    def _compute_amount(self):
        for delivery in self:
            delivery.amount = sum(delivery.line_ids.mapped('amount'))

    @api.model_create_multi
    def create(self, vals_list):
        for vals in vals_list:
            if vals.get('name', self.env._('New')) == self.env._('New'):
                vals['name'] = self.env['ir.sequence'].sudo().next_by_code('ff.demand.delivery') or '/'
        return super().create(vals_list)

    def _ff_invoice(self):
        """Bill the outlet for this delivery. Overridden where invoices live."""
        return True


class FfDemandDeliveryLine(models.Model):
    _name = 'ff.demand.delivery.line'
    _description = 'Delivered Product'

    delivery_id = fields.Many2one('ff.demand.delivery', required=True, index=True, ondelete='cascade')
    demand_line_id = fields.Many2one('ff.demand.line', required=True, index=True, ondelete='cascade')
    product_id = fields.Many2one(related='demand_line_id.product_id', store=True)
    quantity = fields.Float(required=True)
    currency_id = fields.Many2one(related='delivery_id.currency_id')
    amount = fields.Monetary(compute='_compute_amount', store=True)

    @api.depends('quantity', 'demand_line_id.price_total', 'demand_line_id.quantity')
    def _compute_amount(self):
        for line in self:
            asked = line.demand_line_id.quantity
            line.amount = line.demand_line_id.price_total / asked * line.quantity if asked else 0.0
