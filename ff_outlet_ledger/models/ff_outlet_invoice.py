"""What an outlet owes its distributor.

The distributor issues these, not the company, so they stay out of Accounting.
They are kept so that the company can see, per distributor, how much has been
billed to outlets, how much the field has collected and handed over, and how
much is still pending.

An invoice is only Paid once the money against it has been confirmed. Money the
salesperson has collected but nobody has confirmed yet is shown, separately, as
awaiting confirmation, so the two are never mixed up.
"""
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
