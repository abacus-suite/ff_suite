"""What an outlet asked for, before anybody has promised to supply it.

Companies that sell through distributors do not invoice the outlet. The field
collects demand at the counter, the office consolidates it per distributor, and
the distributor is quoted and supplies. A demand is therefore the outlet's
request - the record of who asked for what - and the quotation that follows is
addressed to somebody else entirely.
"""
from odoo import api, fields, models
from odoo.addons.ff_base.tools import parse_client_dt
from odoo.exceptions import UserError

DEMAND_STATES = [
    ('draft', 'Draft'),
    ('submitted', 'Submitted'),
    ('waiting', 'Waiting for Distributor'),
    ('approved', 'Approved'),
    ('rejected', 'Rejected by Distributor'),
    ('quoted', 'Quoted'),
    ('partial', 'Partly Quoted'),
    ('supplied', 'Supplied'),
    ('cancelled', 'Cancelled'),
]


def order_flow(env):
    """'direct' creates sale orders from the app; 'demand' collects demand first."""
    return env['ir.config_parameter'].sudo().get_param('ff_base.order_flow') or 'direct'


class FfDemand(models.Model):
    _name = 'ff.demand'
    _description = 'Outlet Demand'
    _inherit = ['mail.thread']
    _order = 'date desc, id desc'

    name = fields.Char(default=lambda self: self.env._('New'), copy=False, readonly=True)
    employee_id = fields.Many2one('hr.employee', string='Field Employee', required=True,
                                  index=True, ondelete='cascade', tracking=True)
    team_id = fields.Many2one(related='employee_id.ff_team_id', store=True)
    department_id = fields.Many2one(related='employee_id.department_id', store=True)
    partner_id = fields.Many2one('res.partner', string='Outlet', required=True, index=True, tracking=True)
    distributor_id = fields.Many2one('res.partner', string='Distributor', index=True, tracking=True,
                                     domain=[('ff_is_distributor', '=', True)],
                                     help='Who should supply this outlet. Suggested from the outlet or its route.')
    route_id = fields.Many2one('ff.beat', string='Beat', index=True)
    district_id = fields.Many2one(related='partner_id.ff_district_id', store=True)
    visit_id = fields.Many2one('ff.visit', string='Visit', ondelete='set null')
    date = fields.Datetime(required=True, default=fields.Datetime.now, index=True, tracking=True)
    line_ids = fields.One2many('ff.demand.line', 'demand_id', string='Products', copy=True)
    note = fields.Text()

    company_id = fields.Many2one(related='employee_id.company_id', store=True)
    currency_id = fields.Many2one(related='company_id.currency_id')
    amount_untaxed = fields.Monetary(compute='_compute_amounts', store=True, string='Untaxed Value')
    amount_tax = fields.Monetary(compute='_compute_amounts', store=True, string='Taxes')
    amount_total = fields.Monetary(compute='_compute_amounts', store=True, string='Demand Value',
                                   help='What the outlet asked for, taxes included.')
    quantity_total = fields.Float(compute='_compute_amounts', store=True, string='Units')
    quoted_ratio = fields.Float(compute='_compute_amounts', store=True, string='Quoted %')

    state = fields.Selection(DEMAND_STATES, default='submitted', required=True, index=True, tracking=True)
    order_ids = fields.Many2many('sale.order', 'ff_demand_order_rel', 'demand_id', 'order_id',
                                 string='Distributor Quotations', copy=False)
    order_count = fields.Integer(compute='_compute_amounts', store=True)
    request_id = fields.Many2one('ff.demand.request', string='Distributor Request', copy=False, index=True,
                                 ondelete='set null', tracking=True)
    delivery_ids = fields.One2many('ff.demand.delivery', 'demand_id', string='Deliveries')
    delivery_status_id = fields.Many2one('ff.demand.delivery.status', string='Delivery Status',
                                         compute='_compute_delivery', store=True, index=True, tracking=True)
    approved_quantity = fields.Float(compute='_compute_delivery', store=True, string='Approved Units')
    delivered_quantity = fields.Float(compute='_compute_delivery', store=True, string='Delivered Units')
    delivered_amount = fields.Monetary(compute='_compute_delivery', store=True, string='Delivered Value',
                                       help='What the outlet is billed for: only what was delivered.')
    approved_on = fields.Datetime(readonly=True, copy=False)
    reject_note = fields.Char(string='Distributor Remarks', readonly=True, copy=False)
    latitude = fields.Float(digits=(10, 7))
    longitude = fields.Float(digits=(10, 7))
    client_uuid = fields.Char(index=True, copy=False)

    _client_uuid_uniq = models.Constraint('UNIQUE(client_uuid)', 'This demand was already received.')

    @api.depends('line_ids.subtotal', 'line_ids.price_tax', 'line_ids.quantity', 'line_ids.quoted_quantity',
                 'order_ids')
    def _compute_amounts(self):
        for demand in self:
            demand.amount_untaxed = sum(demand.line_ids.mapped('subtotal'))
            demand.amount_tax = sum(demand.line_ids.mapped('price_tax'))
            demand.amount_total = demand.amount_untaxed + demand.amount_tax
            paid = demand._ff_paid_lines()
            demanded = sum(demand.line_ids.mapped('quantity'))
            quoted = sum(paid.mapped('quoted_quantity'))
            demand.quantity_total = demanded
            demanded = sum(paid.mapped('quantity'))
            demand.quoted_ratio = round(quoted / demanded * 100.0, 1) if demanded else 0.0
            demand.order_count = len(demand.order_ids)

    @api.depends('state', 'request_id', 'line_ids.approved_quantity', 'line_ids.delivered_quantity',
                 'line_ids.quantity', 'line_ids.price_total')
    def _compute_delivery(self):
        Status = self.env['ff.demand.delivery.status']
        for demand in self:
            lines = demand.line_ids
            approved = sum(lines.mapped('approved_quantity'))
            delivered = sum(lines.mapped('delivered_quantity'))
            demand.approved_quantity = approved
            demand.delivered_quantity = delivered
            demand.delivered_amount = sum(
                l.price_total / l.quantity * l.delivered_quantity for l in lines if l.quantity)
            code = False
            if demand.request_id and demand.state in ('approved', 'supplied') and approved > 0:
                code = 'progress' if delivered <= 0 else ('partial' if delivered < approved - 0.0001 else 'full')
            demand.delivery_status_id = Status.ff_get(code).id if code else False

    @api.depends('name', 'partner_id')
    def _compute_display_name(self):
        for demand in self:
            demand.display_name = '%s - %s' % (demand.name, demand.partner_id.name or '')

    @api.model_create_multi
    def create(self, vals_list):
        for vals in vals_list:
            if vals.get('name', self.env._('New')) == self.env._('New'):
                vals['name'] = self.env['ir.sequence'].next_by_code('ff.demand') or self.env._('New')
        demands = super().create(vals_list)
        demands._ff_fill_distributor()
        # When a distributor is mapped (from master, route, or app), automatically create
        # and send the distributor request for approval.
        to_request = demands.filtered(lambda d: d.distributor_id and not d.request_id and d.state in ('submitted', 'waiting'))
        by_dist = {}
        for d in to_request:
            by_dist.setdefault(d.distributor_id, self.env['ff.demand'])
            by_dist[d.distributor_id] |= d
        for dist, group in by_dist.items():
            group._ff_make_request(dist)
        return demands

    def _ff_paid_lines(self):
        """The lines that go on a distributor's order; free-of-charge lines are handled elsewhere."""
        self.ensure_one()
        return self.line_ids

    def _ff_fill_distributor(self):
        """Suggest who supplies this outlet: its own distributor, or its route's."""
        for demand in self.filtered(lambda d: not d.distributor_id):
            partner = demand.partner_id.sudo()
            distributor = partner.ff_distributor_id
            if not distributor and 'ff_beat_line_ids' in partner._fields:
                routes = partner.ff_beat_line_ids.beat_id.filtered('ff_distributor_id')
                distributor = routes[:1].ff_distributor_id
            if distributor:
                demand.distributor_id = distributor.id

    # ------------------------------------------------------------------
    # From the app
    # ------------------------------------------------------------------
    @api.model
    def ff_create_from_app(self, employee, partner, data):
        """Record what the outlet asked for. Idempotent on ``uuid``."""
        Demand = self.sudo()
        uuid = data.get('uuid') or False
        if uuid:
            existing = Demand.search([('client_uuid', '=', uuid)], limit=1)
            if existing:
                return existing
        if partner.ff_approval_state != 'approved':
            raise UserError(self.env._('Demand can only be raised for approved contacts.'))
        if partner.ff_category_id and not partner.ff_category_id.allow_orders:
            raise UserError(self.env._('Orders are not allowed for "%s" contacts.', partner.ff_category_id.name))

        Product = self.env['product.product'].sudo()
        lines = []
        for line in data.get('lines') or []:
            quantity = float(line.get('qty') or 0)
            if quantity <= 0:
                continue
            product = Product.browse(int(line.get('product_id') or 0)).exists()
            if not product or not product.sale_ok or not product.product_tmpl_id.ff_show_in_app:
                raise UserError(self.env._('Product %s is not available for field orders.',
                                           line.get('product_id')))
            lines.append((0, 0, {
                'product_id': product.id,
                'quantity': quantity,
                'price_unit': float(line.get('price_unit') or 0) or product.ff_field_price(partner),
            }))
        # Free goods alone are a valid demand: the free lines are added by ff_foc.
        free_only = any(float(f.get('qty') or 0) > 0 for f in (data.get('foc') or []) if isinstance(f, dict))
        if not lines and not free_only:
            raise UserError(self.env._('Add at least one product.'))

        visit = self.env['ff.visit'].sudo().search([
            ('employee_id', '=', employee.id), ('partner_id', '=', partner.id), ('state', '=', 'ongoing'),
        ], limit=1)
        routes = partner.sudo().ff_route_ids if 'ff_route_ids' in partner._fields else False
        # The field picks who should supply this demand; the office's own
        # suggestion fills in afterwards when nothing was chosen.
        distributor = self.env['res.partner'].browse()
        if data.get('distributor_id'):
            distributor = self.env['res.partner'].sudo().browse(int(data['distributor_id'])).exists()
            if not distributor or not distributor.ff_is_distributor:
                raise UserError(self.env._('Choose a distributor from the list.'))
        demand = Demand.create({
            'date': parse_client_dt(data.get('at')) or fields.Datetime.now(),
            'employee_id': employee.id,
            'partner_id': partner.id,
            'visit_id': visit.id or False,
            'route_id': routes[:1].id if routes else False,
            'line_ids': lines,
            'note': (data.get('note') or '').strip() or False,
            'latitude': float(data.get('lat') or 0.0),
            'longitude': float(data.get('lng') or 0.0),
            'client_uuid': uuid,
            'distributor_id': distributor.id or False,
        })
        if visit and not visit.outcome_id:
            outcome = self.env['ff.visit.outcome'].ff_for(employee, partner).filtered('is_order')[:1]
            visit.write({'outcome': 'order', 'outcome_id': outcome.id or False})
        return demand

    def ff_app_payload(self, with_lines=True):
        """What the phone shows for this demand."""
        self.ensure_one()
        labels = {
            'draft': 'Draft', 'submitted': 'Submitted', 'waiting': 'Waiting for distributor',
            'approved': 'Approved', 'rejected': 'Rejected', 'quoted': 'Sent to distributor',
            'partial': 'Partly sent', 'supplied': 'Delivered', 'cancelled': 'Cancelled',
        }
        data = {
            'id': self.id,
            'name': self.name,
            'kind': 'demand',
            'visit_type': self.visit_id.visit_type or None,
            'client': {'id': self.partner_id.id, 'name': self.partner_id.display_name},
            'distributor': {'id': self.distributor_id.id, 'name': self.distributor_id.name} if self.distributor_id else None,
            'request': {'id': self.request_id.id, 'name': self.request_id.name,
                        'state': self.request_id.state,
                        'portal_link': getattr(self.request_id, 'distributor_portal_link', None) or None}
            if self.request_id else None,
            'date': fields.Datetime.to_string(self.date),
            'amount_untaxed': self.amount_untaxed,
            'amount_tax': self.amount_tax,
            'amount_total': self.amount_total,
            'currency': self.currency_id.name,
            'state': self.state,
            'state_label': labels.get(self.state, self.state),
            'quoted_percent': self.quoted_ratio,
            'note': self.note or None,
        }
        if with_lines:
            data['lines'] = [{
                'product': {'id': line.product_id.id, 'name': line.product_id.display_name},
                'sku': line.product_id.product_tmpl_id.ff_sku_code or None,
                'qty': line.quantity,
                'quoted_qty': line.quoted_quantity,
                'price_unit': line.price_unit,
                'subtotal': line.subtotal,
                'tax_percent': line.tax_percent,
                'price_tax': line.price_tax,
                'foc': bool(getattr(line, 'is_foc', False)),
                'foc_note': (line.foc_scheme_id.name or line.foc_reason or None) if getattr(line, 'is_foc', False) else None,
            } for line in self.line_ids]
        return data

    @api.model
    def ff_submit_to_distributor(self, employee, demands, distributor):
        """Send outlet demands to a distributor to be approved.

        No sale order is made: the demands go together as one request, with one
        link. The distributor approves it and later records what they delivered, and
        the outlets are billed for that. A demand the distributor turned down can be
        sent again, to them or to another.
        """
        if not employee.sudo().ff_can_submit_demand:
            raise UserError(self.env._('You cannot send demand to a distributor. Ask the office.'))
        if not distributor or not distributor.sudo().ff_is_distributor:
            raise UserError(self.env._('Choose a distributor.'))
        mine = employee | employee._ff_subordinates()
        demands = demands.sudo().filtered(lambda d: d.employee_id in mine)
        if not demands:
            raise UserError(self.env._('Choose the demands to send.'))
        stale = demands.filtered(lambda d: d.state in ('cancelled', 'supplied', 'approved'))
        if stale:
            raise UserError(self.env._('%s cannot be sent again.', ', '.join(stale.mapped('name'))))
        return demands._ff_make_request(distributor, employee)

    def _ff_make_request(self, distributor, employee=None):
        """One request to ``distributor`` covering these demands, and the link goes out."""
        stale = self.filtered(lambda d: d.state in ('cancelled', 'supplied', 'approved'))
        if stale:
            raise UserError(self.env._('%s cannot be sent again.', ', '.join(stale.mapped('name'))))
        for line in self.mapped('line_ids'):
            line.write({'approved_quantity': 0.0, 'delivered_quantity': 0.0})
        employee = employee or self[:1].employee_id
        request = self.env['ff.demand.request'].sudo().create({
            'partner_id': distributor.id,
            'ff_employee_id': employee.id,
            'company_id': employee.company_id.id,
            'demand_ids': [(6, 0, self.ids)],
        })
        self.write({'distributor_id': distributor.id, 'state': 'waiting', 'reject_note': False})
        request._ff_sent()
        return request

    # ------------------------------------------------------------------
    # Office actions
    # ------------------------------------------------------------------
    def action_cancel(self):
        for demand in self:
            if demand.order_ids:
                raise UserError(self.env._(
                    '%s is already on a distributor quotation. Cancel that first.', demand.name))
            if demand.state in ('approved', 'supplied'):
                raise UserError(self.env._('%s is already approved by the distributor.', demand.name))
            demand.state = 'cancelled'

    def action_reset(self):
        self.filtered(lambda d: d.state == 'cancelled').write({'state': 'submitted'})

    def action_open_orders(self):
        self.ensure_one()
        return {
            'type': 'ir.actions.act_window',
            'name': self.env._('Distributor Quotations'),
            'res_model': 'sale.order',
            'domain': [('id', 'in', self.order_ids.ids)],
            'view_mode': 'list,form',
        }

    # ------------------------------------------------------------------
    # Delivery
    # ------------------------------------------------------------------
    def _ff_sync_delivery(self):
        """After an approval or a delivery: Approved until everything approved is delivered, then Delivered."""
        for demand in self.filtered(lambda d: d.state in ('approved', 'supplied')):
            approved = sum(demand.line_ids.mapped('approved_quantity'))
            delivered = sum(demand.line_ids.mapped('delivered_quantity'))
            full = approved > 0 and delivered >= approved - 0.0001
            demand.state = 'supplied' if full else 'approved'
        self.mapped('request_id')._ff_sync_state()
        self._ff_refresh_state()

    def ff_record_delivery(self, quantities, note=None, entered_by=None):
        """Record what was delivered to this outlet: ``{demand line id: units}``.

        More than what is approved and not yet delivered is refused. The outlet is
        billed for exactly what is recorded here.
        """
        self.ensure_one()
        if self.state != 'approved':
            raise UserError(self.env._('%s is not waiting for delivery.', self.name))
        rows = []
        for line in self.line_ids:
            try:
                units = float(quantities.get(line.id) or 0)
            except (TypeError, ValueError):
                units = 0.0
            if units <= 0:
                continue
            left = line.approved_quantity - line.delivered_quantity
            if units - left > 0.0001:
                raise UserError(self.env._(
                    '%(product)s: only %(left)s left to deliver.', product=line.product_id.display_name, left='%g' % left))
            rows.append((0, 0, {'demand_line_id': line.id, 'quantity': units}))
        if not rows:
            raise UserError(self.env._('Enter the quantity delivered.'))
        delivery = self.env['ff.demand.delivery'].sudo().create({
            'demand_id': self.id, 'note': (note or '').strip() or False,
            'entered_by': entered_by or self.env.user.name, 'line_ids': rows,
        })
        for row in delivery.line_ids:
            row.demand_line_id.sudo().delivered_quantity += row.quantity
        self._ff_sync_delivery()
        delivery._ff_invoice()
        self.message_post(body=self.env._('Delivery %(name)s recorded by %(who)s.', name=delivery.name,
                                          who=delivery.entered_by or ''))
        if 'ff.notification' in self.env and self.employee_id:
            self.env['ff.notification'].sudo().ff_push(
                title=self.env._('Demand Delivered'),
                body=self.env._('Delivery %(name)s recorded for %(outlet)s (%(demand)s) by %(who)s.',
                                name=delivery.name,
                                outlet=self.partner_id.name,
                                demand=self.name,
                                who=self.distributor_id.name or delivery.entered_by or 'distributor'),
                kind='info',
                employee=self.employee_id,
                record=self,
            )
        return delivery

    def ff_close_delivery(self, note=None):
        """The distributor cannot supply what is left: what was delivered is final."""
        for demand in self:
            if demand.state != 'approved':
                raise UserError(self.env._('%s is not waiting for delivery.', demand.name))
            for line in demand.line_ids:
                line.sudo().approved_quantity = line.delivered_quantity
            if not sum(demand.line_ids.mapped('delivered_quantity')):
                demand.sudo().write({'state': 'rejected', 'reject_note': note or self.env._('Nothing was delivered.')})
                demand.request_id._ff_sync_state()
            else:
                demand._ff_sync_delivery()
            demand.message_post(body=self.env._('Delivery closed. The rest could not be supplied. %s', note or ''))
        return True

    def action_ff_close_delivery(self):
        return self.ff_close_delivery()

    def _ff_refresh_state(self):
        """Quoted, partly quoted or supplied, read from the lines and the orders."""
        for demand in self:
            if demand.state == 'cancelled' or demand.request_id:
                continue
            paid = demand._ff_paid_lines()
            demanded = sum(paid.mapped('quantity'))
            quoted = sum(paid.mapped('quoted_quantity'))
            if demand.order_ids and all(order.state == 'sale' for order in demand.order_ids) and quoted >= demanded:
                demand.state = 'supplied'
            elif quoted <= 0:
                demand.state = 'submitted'
            elif quoted < demanded:
                demand.state = 'partial'
            else:
                demand.state = 'quoted'


class FfDemandLine(models.Model):
    _name = 'ff.demand.line'
    _description = 'Demanded Product'
    _order = 'demand_id, id'

    demand_id = fields.Many2one('ff.demand', required=True, index=True, ondelete='cascade')
    partner_id = fields.Many2one(related='demand_id.partner_id', store=True, string='Outlet')
    distributor_id = fields.Many2one(related='demand_id.distributor_id', store=True, index=True)
    employee_id = fields.Many2one(related='demand_id.employee_id', store=True, index=True)
    date = fields.Datetime(related='demand_id.date', store=True, index=True)
    state = fields.Selection(related='demand_id.state', store=True, index=True)
    product_id = fields.Many2one('product.product', required=True, index=True)
    quantity = fields.Float(string='Demanded', required=True, default=1.0)
    quoted_quantity = fields.Float(string='Quoted', readonly=True, copy=False)
    approved_quantity = fields.Float(string='Approved', readonly=True, copy=False,
                                     help='What the distributor agreed to supply.')
    delivered_quantity = fields.Float(string='Delivered', readonly=True, copy=False,
                                      help='What has actually reached the outlet. The outlet pays for this.')
    uom_id = fields.Many2one(related='product_id.uom_id', string='Unit')
    price_unit = fields.Monetary(string='PTR')
    currency_id = fields.Many2one(related='demand_id.currency_id')
    subtotal = fields.Monetary(compute='_compute_subtotal', store=True, string='Untaxed')
    tax_ids = fields.Many2many('account.tax', 'ff_demand_line_tax_rel', 'line_id', 'tax_id', string='Taxes',
                               domain=[('type_tax_use', '=', 'sale')], check_company=False)
    price_tax = fields.Monetary(compute='_compute_subtotal', store=True, string='Tax Amount')
    price_total = fields.Monetary(compute='_compute_subtotal', store=True, string='Total')
    tax_percent = fields.Float(compute='_compute_tax_percent', string='Tax %', digits=(5, 2))

    @api.depends('quantity', 'price_unit', 'tax_ids')
    def _compute_subtotal(self):
        for line in self:
            untaxed = line.quantity * line.price_unit
            tax = 0.0
            if line.tax_ids and untaxed:
                result = line.tax_ids.compute_all(
                    line.price_unit, currency=line.currency_id, quantity=line.quantity,
                    product=line.product_id, partner=line.partner_id)
                untaxed = result['total_excluded']
                tax = result['total_included'] - result['total_excluded']
            line.subtotal = untaxed
            line.price_tax = tax
            line.price_total = untaxed + tax

    @api.depends('tax_ids')
    def _compute_tax_percent(self):
        for line in self:
            line.tax_percent = sum(t.amount for t in line.tax_ids if t.amount_type == 'percent')

    @api.model
    def _ff_default_taxes(self, product, company):
        """The sales taxes the product carries in this company."""
        return product.sudo().taxes_id.filtered(lambda t: t.company_id == company)

    @api.model_create_multi
    def create(self, vals_list):
        Product = self.env['product.product'].sudo()
        Demand = self.env['ff.demand'].sudo()
        for vals in vals_list:
            if 'tax_ids' not in vals and vals.get('product_id') and vals.get('demand_id'):
                company = Demand.browse(vals['demand_id']).company_id
                taxes = self._ff_default_taxes(Product.browse(vals['product_id']), company)
                if taxes:
                    vals['tax_ids'] = [(6, 0, taxes.ids)]
        return super().create(vals_list)

    @api.onchange('product_id')
    def _onchange_product(self):
        for line in self.filtered('product_id'):
            line.price_unit = line.product_id.ff_field_price(line.demand_id.partner_id)
            line.tax_ids = self._ff_default_taxes(line.product_id, line.demand_id.company_id or self.env.company)

    @property
    def pending_quantity(self):
        return max(self.quantity - self.quoted_quantity, 0.0)
