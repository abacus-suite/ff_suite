"""Money an outlet paid towards a distributor's invoices.

The salesperson collects it at the outlet and hands it to the distributor. The
company only needs to know it happened and how it was applied, so this is a
record and not an accounting entry. It becomes confirmed when somebody on the
office side has checked it; until then the invoices show it as awaiting
confirmation, not as paid.
"""
from odoo import api, fields, models
from odoo.exceptions import AccessError, UserError, ValidationError


class FfOutletPayment(models.Model):
    _name = 'ff.outlet.payment'
    _description = 'Outlet Payment'
    _inherit = ['mail.thread']
    _order = 'date desc, id desc'

    name = fields.Char(default=lambda self: self.env._('New'), copy=False, readonly=True)
    collection_id = fields.Many2one('ff.collection', string='Collection', index=True, readonly=True,
                                    ondelete='set null', copy=False)
    employee_id = fields.Many2one('hr.employee', string='Collected by', required=True, index=True,
                                  ondelete='cascade')
    team_id = fields.Many2one(related='employee_id.ff_team_id', store=True)
    partner_id = fields.Many2one('res.partner', string='Outlet', required=True, index=True, tracking=True)
    distributor_id = fields.Many2one('res.partner', string='Given to', required=True, index=True,
                                     domain=[('ff_is_distributor', '=', True)], tracking=True)
    date = fields.Datetime(required=True, default=fields.Datetime.now, index=True)
    mode_id = fields.Many2one('ff.collection.mode', string='Mode')
    reference = fields.Char(string='Reference / Cheque No.')
    company_id = fields.Many2one('res.company', required=True, default=lambda self: self.env.company)
    currency_id = fields.Many2one(related='company_id.currency_id')
    amount = fields.Monetary(required=True, tracking=True)
    line_ids = fields.One2many('ff.outlet.payment.line', 'payment_id', string='Applied To')
    amount_applied = fields.Monetary(compute='_compute_applied', store=True)
    amount_unapplied = fields.Monetary(string='On Account', compute='_compute_applied', store=True,
                                       help='Collected but not tied to an invoice.')
    note = fields.Text()
    state = fields.Selection([
        ('given', 'Given to Distributor'), ('confirmed', 'Confirmed'), ('rejected', 'Rejected'),
    ], default='given', required=True, index=True, tracking=True)
    confirmed_by_id = fields.Many2one('res.users', readonly=True, copy=False)
    confirmed_at = fields.Datetime(readonly=True, copy=False)

    @api.depends('amount', 'line_ids.amount')
    def _compute_applied(self):
        for payment in self:
            payment.amount_applied = sum(payment.line_ids.mapped('amount'))
            payment.amount_unapplied = payment.amount - payment.amount_applied

    @api.constrains('amount', 'line_ids')
    def _check_applied(self):
        for payment in self:
            if payment.amount <= 0:
                raise ValidationError(self.env._('A payment must be for more than zero.'))
            if payment.amount_applied - payment.amount > 0.005:
                raise ValidationError(self.env._(
                    '%(name)s applies more than was collected.', name=payment.display_name))

    @api.depends('name', 'partner_id')
    def _compute_display_name(self):
        for payment in self:
            payment.display_name = '%s - %s' % (payment.name, payment.partner_id.name or '')

    @api.model_create_multi
    def create(self, vals_list):
        for vals in vals_list:
            if vals.get('name', self.env._('New')) == self.env._('New'):
                vals['name'] = self.env['ir.sequence'].sudo().next_by_code('ff.outlet.payment') or '/'
        return super().create(vals_list)

    # ------------------------------------------------------------------
    # Applying it
    # ------------------------------------------------------------------
    @api.model
    def ff_record(self, collection, allocations):
        """Make the payment behind a collection, applied to the invoices named.

        ``allocations`` is ``[{invoice_id, amount}]``. Whatever is left over is
        simply on account. An invoice must belong to this outlet and may not be
        applied beyond what is still pending on it.
        """
        Invoice = self.env['ff.outlet.invoice'].sudo()
        lines = []
        remaining = collection.amount
        for row in allocations or []:
            invoice = Invoice.browse(int(row.get('invoice_id') or 0)).exists()
            if not invoice or invoice.partner_id.commercial_partner_id != collection.partner_id.commercial_partner_id:
                raise UserError(self.env._('That invoice does not belong to this outlet.'))
            try:
                amount = float(row.get('amount') or 0)
            except (TypeError, ValueError):
                continue
            if amount <= 0:
                continue
            if amount - invoice.amount_pending > 0.005:
                raise UserError(self.env._(
                    '%(invoice)s has only %(left)s pending.', invoice=invoice.name, left=invoice.amount_pending))
            amount = min(amount, remaining)
            if amount <= 0:
                break
            remaining -= amount
            lines.append((0, 0, {'invoice_id': invoice.id, 'amount': amount}))
        return self.sudo().create({
            'collection_id': collection.id,
            'employee_id': collection.employee_id.id,
            'partner_id': collection.partner_id.id,
            'distributor_id': collection.distributor_id.id,
            'date': collection.date,
            'mode_id': collection.mode_id.id,
            'reference': collection.reference,
            'amount': collection.amount,
            'company_id': collection.company_id.id,
            'note': collection.note,
            'line_ids': lines,
        })

    # ------------------------------------------------------------------
    # Verifying it
    # ------------------------------------------------------------------
    def _ff_check_verifier(self):
        if not (self.env.user.has_group('ff_base.group_ff_manager') or self.env.user.has_group('account.group_account_user')):
            raise AccessError(self.env._('Only a manager or accounting can confirm outlet payments.'))

    def action_confirm(self):
        self._ff_check_verifier()
        for payment in self:
            if payment.state != 'given':
                raise UserError(self.env._('%s has already been dealt with.', payment.display_name))
        self.sudo().write({'state': 'confirmed', 'confirmed_by_id': self.env.uid,
                           'confirmed_at': fields.Datetime.now()})

    def action_reject(self):
        self._ff_check_verifier()
        for payment in self:
            if payment.state != 'given':
                raise UserError(self.env._('%s has already been dealt with.', payment.display_name))
        self.sudo().write({'state': 'rejected', 'confirmed_by_id': self.env.uid,
                           'confirmed_at': fields.Datetime.now()})

    def action_reset(self):
        self._ff_check_verifier()
        self.sudo().write({'state': 'given', 'confirmed_by_id': False, 'confirmed_at': False})


class FfOutletPaymentLine(models.Model):
    _name = 'ff.outlet.payment.line'
    _description = 'Outlet Payment Applied To An Invoice'

    payment_id = fields.Many2one('ff.outlet.payment', required=True, ondelete='cascade', index=True)
    invoice_id = fields.Many2one('ff.outlet.invoice', required=True, ondelete='restrict', index=True)
    amount = fields.Monetary(required=True)
    currency_id = fields.Many2one(related='payment_id.currency_id')
    state = fields.Selection(related='payment_id.state', store=True)
