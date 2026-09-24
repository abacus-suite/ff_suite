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
    route_id = fields.Many2one('ff.beat', string='Route', index=True)
    district_id = fields.Many2one(related='partner_id.ff_district_id', store=True)
    visit_id = fields.Many2one('ff.visit', string='Visit', ondelete='set null')
    date = fields.Datetime(required=True, default=fields.Datetime.now, index=True, tracking=True)
    line_ids = fields.One2many('ff.demand.line', 'demand_id', string='Products', copy=True)
    note = fields.Text()

    company_id = fields.Many2one(related='employee_id.company_id', store=True)
    currency_id = fields.Many2one(related='company_id.currency_id')
    amount_total = fields.Monetary(compute='_compute_amounts', store=True, string='Demand Value')
    quantity_total = fields.Float(compute='_compute_amounts', store=True, string='Units')
    quoted_ratio = fields.Float(compute='_compute_amounts', store=True, string='Quoted %')

    state = fields.Selection(DEMAND_STATES, default='submitted', required=True, index=True, tracking=True)
    order_ids = fields.Many2many('sale.order', 'ff_demand_order_rel', 'demand_id', 'order_id',
                                 string='Distributor Quotations', copy=False)
    order_count = fields.Integer(compute='_compute_amounts', store=True)
    latitude = fields.Float(digits=(10, 7))
    longitude = fields.Float(digits=(10, 7))
    client_uuid = fields.Char(index=True, copy=False)

    _client_uuid_uniq = models.Constraint('UNIQUE(client_uuid)', 'This demand was already received.')

    @api.depends('line_ids.subtotal', 'line_ids.quantity', 'line_ids.quoted_quantity', 'order_ids')
    def _compute_amounts(self):
        for demand in self:
            demand.amount_total = sum(demand.line_ids.mapped('subtotal'))
            demanded = sum(demand.line_ids.mapped('quantity'))
            quoted = sum(demand.line_ids.mapped('quoted_quantity'))
            demand.quantity_total = demanded
            demand.quoted_ratio = round(quoted / demanded * 100.0, 1) if demanded else 0.0
            demand.order_count = len(demand.order_ids)

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
        return demands

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
                'price_unit': float(line.get('price_unit') or 0) or product.ff_field_price(),
            }))
        if not lines:
            raise UserError(self.env._('Add at least one product.'))

        visit = self.env['ff.visit'].sudo().search([
            ('employee_id', '=', employee.id), ('partner_id', '=', partner.id), ('state', '=', 'ongoing'),
        ], limit=1)
        routes = partner.sudo().ff_route_ids if 'ff_route_ids' in partner._fields else False
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
        })
        if visit and not visit.outcome_id:
            outcome = self.env['ff.visit.outcome'].ff_for(employee, partner).filtered('is_order')[:1]
            visit.write({'outcome': 'order', 'outcome_id': outcome.id or False})
        return demand

    def ff_app_payload(self, with_lines=True):
        """What the phone shows for this demand."""
        self.ensure_one()
        labels = {
            'draft': 'Draft', 'submitted': 'Submitted', 'quoted': 'Sent to distributor',
            'partial': 'Partly sent', 'supplied': 'Supplied', 'cancelled': 'Cancelled',
        }
        data = {
            'id': self.id,
            'name': self.name,
            'kind': 'demand',
            'client': {'id': self.partner_id.id, 'name': self.partner_id.display_name},
            'date': fields.Datetime.to_string(self.date),
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
                'foc': bool(getattr(line, 'is_foc', False)),
                'foc_note': (line.foc_scheme_id.name or line.foc_reason or None) if getattr(line, 'is_foc', False) else None,
            } for line in self.line_ids]
        return data

    # ------------------------------------------------------------------
    # Office actions
    # ------------------------------------------------------------------
    def action_cancel(self):
        for demand in self:
            if demand.order_ids:
                raise UserError(self.env._(
                    '%s is already on a distributor quotation. Cancel that first.', demand.name))
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

    def _ff_refresh_state(self):
        """Quoted, partly quoted or supplied, read from the lines and the orders."""
        for demand in self:
            if demand.state == 'cancelled':
                continue
            demanded = sum(demand.line_ids.mapped('quantity'))
            quoted = sum(demand.line_ids.mapped('quoted_quantity'))
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
    uom_id = fields.Many2one(related='product_id.uom_id', string='Unit')
    price_unit = fields.Monetary(string='PTR')
    currency_id = fields.Many2one(related='demand_id.currency_id')
    subtotal = fields.Monetary(compute='_compute_subtotal', store=True)

    @api.depends('quantity', 'price_unit')
    def _compute_subtotal(self):
        for line in self:
            line.subtotal = line.quantity * line.price_unit

    @api.onchange('product_id')
    def _onchange_product(self):
        for line in self.filtered('product_id'):
            line.price_unit = line.product_id.ff_field_price()

    @property
    def pending_quantity(self):
        return max(self.quantity - self.quoted_quantity, 0.0)
