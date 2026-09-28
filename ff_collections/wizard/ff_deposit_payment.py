"""Receiving a deposit, and posting the money in the same breath.

Until now the office marked a deposit received and then went to Accounting to
enter the customer payments by hand, from the same list of collections. That is
the same work twice, and the two drift apart the moment somebody is busy. So
receiving opens the payment form instead: the total is already there, the
office picks the journal the money went into, and confirming posts the payments
and receives the deposit together.

The money came from customers, not from the employee, so by default one payment
is posted per customer. One payment for the whole deposit is offered for offices
that bank it as a single line and reconcile afterwards.
"""
from odoo import api, fields, models
from odoo.exceptions import UserError


class FfDepositPayment(models.TransientModel):
    _name = 'ff.deposit.payment'
    _description = 'Receive Deposit and Post Payments'

    deposit_id = fields.Many2one('ff.collection.deposit', required=True, ondelete='cascade')
    company_id = fields.Many2one(related='deposit_id.company_id')
    currency_id = fields.Many2one(related='deposit_id.currency_id')
    employee_id = fields.Many2one(related='deposit_id.employee_id')
    amount = fields.Monetary(string='Amount', readonly=True,
                             help='The total handed over. It is the sum of the collections and cannot be edited here.')
    collection_count = fields.Integer(related='deposit_id.collection_count')
    partner_count = fields.Integer(compute='_compute_partner_count', string='Customers')

    journal_id = fields.Many2one(
        'account.journal', string='Journal', required=True,
        domain="[('type', 'in', ('bank', 'cash')), ('company_id', '=', company_id)]",
        help='Where the money went: the cash box, or the bank account it was paid into.')
    payment_method_line_id = fields.Many2one(
        'account.payment.method.line', string='Payment Method',
        domain="[('id', 'in', available_method_line_ids)]")
    available_method_line_ids = fields.Many2many(
        'account.payment.method.line', compute='_compute_available_method_lines')
    payment_date = fields.Date(string='Payment Date', required=True, default=fields.Date.context_today)
    memo = fields.Char(string='Memo', help='Written on every payment this creates.')
    group_payments = fields.Selection([
        ('per_partner', 'One payment per customer'),
        ('single', 'One payment for the whole deposit'),
    ], string='Post as', default='per_partner', required=True)
    single_partner_id = fields.Many2one(
        'res.partner', string='Received From',
        help='Who the single payment is recorded against when the deposit is banked as one line.')

    @api.depends('deposit_id')
    def _compute_partner_count(self):
        for wizard in self:
            wizard.partner_count = len(wizard.deposit_id.collection_ids.partner_id)

    @api.depends('journal_id')
    def _compute_available_method_lines(self):
        for wizard in self:
            wizard.available_method_line_ids = wizard.journal_id.inbound_payment_method_line_ids

    @api.onchange('journal_id')
    def _onchange_journal(self):
        for wizard in self:
            lines = wizard.journal_id.inbound_payment_method_line_ids
            if wizard.payment_method_line_id not in lines:
                wizard.payment_method_line_id = lines[:1].id

    @api.model
    def default_get(self, fields_list):
        values = super().default_get(fields_list)
        deposit = self.env['ff.collection.deposit'].browse(
            self.env.context.get('active_id') or values.get('deposit_id'))
        if not deposit:
            return values
        if deposit.state != 'submitted':
            raise UserError(self.env._('Only a submitted deposit can be received.'))
        journal = self.env['account.journal'].search([
            ('type', 'in', ('bank', 'cash')), ('company_id', '=', deposit.company_id.id),
        ], limit=1)
        values.update(
            deposit_id=deposit.id,
            amount=deposit.amount,
            memo=deposit.reference or deposit.name,
            journal_id=journal.id or False,
            payment_method_line_id=journal.inbound_payment_method_line_ids[:1].id or False,
        )
        return values

    def action_confirm(self):
        """Post the payments, then receive the deposit."""
        self.ensure_one()
        deposit = self.deposit_id
        deposit._ff_check_approver()
        if deposit.state != 'submitted':
            raise UserError(self.env._('Only a submitted deposit can be received.'))
        collections = deposit.collection_ids
        if not collections:
            raise UserError(self.env._('There is nothing on this deposit to post.'))

        Payment = self.env['account.payment'].sudo()
        payments = Payment.browse()
        if self.group_payments == 'single':
            partner = self.single_partner_id or collections[:1].partner_id
            payments |= self._ff_payment(partner, deposit.amount, collections)
        else:
            for partner in collections.partner_id:
                lines = collections.filtered(lambda c, p=partner: c.partner_id == p)
                payments |= self._ff_payment(partner, sum(lines.mapped('amount')), lines)
        payments.action_post()

        deposit.action_receive()
        deposit.message_post(body=self.env._(
            'Money received into %(journal)s. Posted: %(payments)s.',
            journal=self.journal_id.display_name,
            payments=', '.join(payments.mapped('name')) or self.env._('nothing')))
        return {
            'type': 'ir.actions.act_window',
            'name': self.env._('Payments'),
            'res_model': 'account.payment',
            'domain': [('id', 'in', payments.ids)],
            'view_mode': 'list,form' if len(payments) > 1 else 'form',
            'res_id': payments.id if len(payments) == 1 else False,
        }

    def _ff_payment(self, partner, amount, collections):
        """One posted customer payment, tied back to the collections it settles."""
        Payment = self.env['account.payment'].sudo()
        vals = {
            'payment_type': 'inbound',
            'partner_type': 'customer',
            'partner_id': partner.id,
            'amount': amount,
            'date': self.payment_date,
            'journal_id': self.journal_id.id,
            'company_id': self.company_id.id,
            'currency_id': self.currency_id.id,
        }
        if self.payment_method_line_id:
            vals['payment_method_line_id'] = self.payment_method_line_id.id
        # The field holding the payment's own note has been renamed over the years.
        note = self.memo or self.deposit_id.name
        for field in ('memo', 'ref', 'communication'):
            if field in Payment._fields:
                vals[field] = note
                break
        payment = Payment.create(vals)
        collections.write({'payment_id': payment.id})
        return payment
