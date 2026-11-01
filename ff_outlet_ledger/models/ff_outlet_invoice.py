"""What an outlet owes its distributor.

The distributor issues these, not the company, so they stay out of Accounting.
They are kept so that the company can see, per distributor, how much has been
billed to outlets, how much the field has collected and handed over, and how
much is still pending.

An invoice is only Paid once the money against it has been confirmed. Money the
salesperson has collected but nobody has confirmed yet is shown, separately, as
awaiting confirmation, so the two are never mixed up.
"""
from datetime import timedelta

from odoo import api, fields, models
from odoo.exceptions import UserError


class FfOutletInvoice(models.Model):
    _name = 'ff.outlet.invoice'
    _description = 'Outlet Invoice'
    _inherit = ['mail.thread']
    _order = 'date desc, id desc'

    name = fields.Char(string='Invoice No.', required=True, copy=False, tracking=True)
    distributor_id = fields.Many2one('res.partner', string='Distributor', required=True, index=True,
                                     domain=[('ff_is_distributor', '=', True)], tracking=True)
    partner_id = fields.Many2one('res.partner', string='Outlet', required=True, index=True, tracking=True)
    employee_id = fields.Many2one('hr.employee', string='Entered by', index=True, ondelete='set null',
                                  default=lambda self: self.env.user.employee_id)
    team_id = fields.Many2one(related='employee_id.ff_team_id', store=True)
    date = fields.Date(string='Invoice Date', required=True, default=fields.Date.context_today, index=True)
    due_date = fields.Date(string='Due Date', index=True)
    company_id = fields.Many2one('res.company', required=True, default=lambda self: self.env.company)
    currency_id = fields.Many2one(related='company_id.currency_id')
    amount_total = fields.Monetary(string='Amount', required=True, tracking=True)
    note = fields.Text()
    payment_line_ids = fields.One2many('ff.outlet.payment.line', 'invoice_id', string='Payments')
    demand_id = fields.Many2one('ff.demand', string='Demand', index=True, ondelete='set null', copy=False)
    delivery_id = fields.Many2one('ff.demand.delivery', string='Delivery', index=True, ondelete='set null', copy=False)
    order_id = fields.Many2one('sale.order', string='Distributor Order', index=True, ondelete='set null', copy=False)

    amount_collected = fields.Monetary(string='Collected', compute='_compute_amounts', store=True,
                                       help='Everything the field has collected against it, confirmed or not.')
    amount_confirmed = fields.Monetary(string='Confirmed', compute='_compute_amounts', store=True,
                                       help='Collected money that has been confirmed.')
    amount_awaiting = fields.Monetary(string='Awaiting Confirmation', compute='_compute_amounts', store=True)
    amount_pending = fields.Monetary(string='Pending', compute='_compute_amounts', store=True,
                                     help='What is still to be collected: the amount less everything collected.')
    earning = fields.Monetary(string='Distributor Earning', compute='_compute_amounts', store=True,
                              help="The distributor's share of the confirmed money, at its earning %.")
    state = fields.Selection([
        ('open', 'Open'), ('partial', 'Part Paid'), ('paid', 'Paid'), ('cancelled', 'Cancelled'),
    ], compute='_compute_amounts', store=True, index=True, tracking=True)
    cancelled = fields.Boolean(copy=False)
    overdue = fields.Boolean(compute='_compute_overdue', search='_search_overdue')

    _name_distributor_uniq = models.Constraint(
        'UNIQUE(name, distributor_id)', 'This distributor already has an invoice with that number.')

    @api.depends('amount_total', 'cancelled', 'distributor_id.ff_earning_pct',
                 'payment_line_ids.amount', 'payment_line_ids.payment_id.state')
    def _compute_amounts(self):
        for invoice in self:
            lines = invoice.payment_line_ids.filtered(lambda l: l.payment_id.state != 'rejected')
            collected = sum(lines.mapped('amount'))
            confirmed = sum(lines.filtered(lambda l: l.payment_id.state == 'confirmed').mapped('amount'))
            invoice.amount_collected = collected
            invoice.amount_confirmed = confirmed
            invoice.amount_awaiting = collected - confirmed
            invoice.amount_pending = max(invoice.amount_total - collected, 0.0)
            invoice.earning = confirmed * (invoice.distributor_id.ff_earning_pct or 0.0) / 100.0
            if invoice.cancelled:
                invoice.state = 'cancelled'
            elif invoice.amount_total and confirmed >= invoice.amount_total:
                invoice.state = 'paid'
            elif collected > 0:
                invoice.state = 'partial'
            else:
                invoice.state = 'open'

    def _compute_overdue(self):
        today = fields.Date.context_today(self)
        for invoice in self:
            invoice.overdue = bool(invoice.due_date and invoice.due_date < today
                                   and invoice.state in ('open', 'partial'))

    def _search_overdue(self, operator, value):
        today = fields.Date.context_today(self)
        wanted = (operator == '=') == bool(value)
        domain = [('due_date', '<', today), ('state', 'in', ('open', 'partial'))]
        return domain if wanted else ['!'] + domain

    @api.depends('name', 'partner_id')
    def _compute_display_name(self):
        for invoice in self:
            invoice.display_name = '%s - %s' % (invoice.name, invoice.partner_id.name or '')

    @api.model
    def _ff_due_date(self, partner, date):
        """When an invoice to ``partner`` falls due: its credit days, else its payment terms, else the default."""
        ICP = self.env['ir.config_parameter'].sudo()
        partner = partner.sudo().commercial_partner_id
        days = getattr(partner, 'ff_credit_days', 0) or 0
        if days > 0:
            return date + timedelta(days=days)
        term = partner.property_payment_term_id
        if not term:
            term_id = int(ICP.get_param('ff_base.invoice_payment_term_id') or 0)
            term = self.env['account.payment.term'].sudo().browse(term_id).exists()
        if term and term.line_ids:
            last = term.line_ids.sorted('id')[-1]
            nb = getattr(last, 'nb_days', 0) or 0
            kind = getattr(last, 'delay_type', 'days_after')
            due = date + timedelta(days=nb)
            if kind == 'days_after_end_of_month':
                due = (date.replace(day=1) + timedelta(days=32)).replace(day=1) - timedelta(days=1) + timedelta(days=nb)
            return due
        return date + timedelta(days=int(ICP.get_param('ff_base.invoice_due_days') or 30))

    @api.model
    def ff_from_order(self, order):
        """One invoice per outlet demand in an order the distributor has accepted.

        Priced as the outlet asked, scaled by what the distributor actually accepted of each
        product, and free goods carry nothing. Raised once per demand.
        """
        order = order.sudo()
        today = fields.Date.context_today(self)
        made = self.browse()
        accepted = {}
        for line in order.order_line.filtered(lambda l: not l.display_type and not getattr(l, 'ff_is_foc', False)):
            accepted[line.product_id.id] = accepted.get(line.product_id.id, 0.0) + line.product_uom_qty
        asked = {}
        for demand in order.ff_demand_ids:
            for dl in demand.line_ids.filtered(lambda l: not getattr(l, 'is_foc', False)):
                asked[dl.product_id.id] = asked.get(dl.product_id.id, 0.0) + (dl.quoted_quantity or dl.quantity)
        for demand in order.ff_demand_ids:
            if self.sudo().search_count([('demand_id', '=', demand.id)]):
                continue
            amount = 0.0
            for dl in demand.line_ids.filtered(lambda l: not getattr(l, 'is_foc', False)):
                pid = dl.product_id.id
                ratio = accepted.get(pid, 0.0) / asked[pid] if asked.get(pid) else 1.0
                amount += dl.price_total * ratio
            if amount <= 0:
                continue
            made |= self.sudo().create({
                'name': self.env['ir.sequence'].sudo().next_by_code('ff.outlet.invoice') or '/',
                'distributor_id': order.partner_id.id,
                'partner_id': demand.partner_id.id,
                'employee_id': demand.employee_id.id,
                'date': today,
                'due_date': self._ff_due_date(demand.partner_id, today),
                'amount_total': round(amount, 2),
                'company_id': order.company_id.id,
                'demand_id': demand.id,
                'order_id': order.id,
                'note': self.env._('Raised from %(demand)s on %(order)s.', demand=demand.name, order=order.name),
            })
        return made

    def action_cancel(self):
        self.write({'cancelled': True})

    def action_reopen(self):
        self.write({'cancelled': False})

    # ------------------------------------------------------------------
    # From the app
    # ------------------------------------------------------------------
    @api.model
    def ff_create_from_app(self, employee, data):
        """A salesperson enters an invoice they have seen at the outlet."""
        Partner = self.env['res.partner'].sudo()
        outlet = Partner.browse(int(data.get('partner_id') or 0)).exists()
        if not outlet:
            raise UserError(self.env._('Choose the outlet.'))
        distributor = Partner.browse(int(data.get('distributor_id') or 0)).exists() or outlet.ff_distributor_id
        if not distributor:
            raise UserError(self.env._('This outlet has no distributor. Choose the one that billed it.'))
        number = (data.get('number') or '').strip()
        if not number:
            raise UserError(self.env._('Enter the invoice number.'))
        try:
            amount = float(data.get('amount'))
        except (TypeError, ValueError):
            amount = 0.0
        if amount <= 0:
            raise UserError(self.env._('Enter the invoice amount.'))
        existing = self.sudo().search([('name', '=', number), ('distributor_id', '=', distributor.id)], limit=1)
        if existing:
            return existing
        return self.sudo().create({
            'name': number,
            'company_id': employee.sudo().company_id.id,
            'distributor_id': distributor.id,
            'partner_id': outlet.id,
            'employee_id': employee.id,
            'date': fields.Date.to_date(data.get('date')) or fields.Date.context_today(self),
            'due_date': fields.Date.to_date(data.get('due_date')) or False,
            'amount_total': amount,
            'note': (data.get('note') or '').strip() or False,
            'company_id': employee.company_id.id,
        })

    def ff_app_payload(self):
        self.ensure_one()
        return {
            'id': self.id,
            'number': self.name,
            'outlet': {'id': self.partner_id.id, 'name': self.partner_id.display_name},
            'distributor': {'id': self.distributor_id.id, 'name': self.distributor_id.display_name},
            'date': fields.Date.to_string(self.date),
            'due_date': fields.Date.to_string(self.due_date) if self.due_date else None,
            'amount': self.amount_total,
            'collected': self.amount_collected,
            'confirmed': self.amount_confirmed,
            'pending': self.amount_pending,
            'state': self.state,
            'overdue': self.overdue,
            'currency': self.currency_id.name,
        }
