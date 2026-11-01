# -*- coding: utf-8 -*-
from odoo import api, fields, models, _
from odoo.exceptions import UserError


class L4eLoanSettleWizard(models.TransientModel):
    _name = 'l4e.loan.settle.wizard'
    _description = 'Loan Pre-closure & Settlement Wizard'

    loan_id = fields.Many2one('l4e.loan', string='Loan', required=True, readonly=True)
    employee_id = fields.Many2one('hr.employee', related='loan_id.employee_id', string='Employee', readonly=True)
    currency_id = fields.Many2one('res.currency', related='loan_id.currency_id')
    settlement_amount = fields.Monetary(string='Settlement Amount (₹)', required=True)
    settlement_date = fields.Date(string='Settlement Date', default=fields.Date.context_today, required=True)
    payment_mode = fields.Selection([
        ('bank', 'Bank Transfer / UPI'),
        ('cash', 'Cash'),
        ('salary_deduct', 'One-time Full Salary Deduction'),
        ('other', 'Other'),
    ], string='Settlement Mode', default='bank', required=True)
    note = fields.Text(string='Settlement Remarks')

    def action_confirm_settlement(self):
        self.ensure_one()
        loan = self.loan_id
        if loan.state != 'disbursed':
            raise UserError(_("Only active disbursed loans can be settled."))

        unpaid_lines = loan.installment_ids.filtered(lambda l: l.state in ('pending', 'overdue'))
        if not unpaid_lines:
            raise UserError(_("There are no pending installments left to settle."))

        # Mark all pending/overdue lines as paid
        for line in unpaid_lines:
            line.write({
                'state': 'paid',
                'paid_date': self.settlement_date,
                'note': _("Settled via Pre-closure (%s)") % dict(self._fields['payment_mode'].selection).get(self.payment_mode),
            })

        mode_label = dict(self._fields['payment_mode'].selection).get(self.payment_mode)
        loan.message_post(body=_(
            "<b>🤝 Loan Pre-closed / Settled in Full:</b><br/>"
            "• Amount Paid: ₹ %s<br/>"
            "• Date: %s<br/>"
            "• Payment Mode: %s<br/>"
            "• Remarks: %s<br/>"
            "• Settled by: %s"
        ) % (
            "{:,.2f}".format(self.settlement_amount),
            self.settlement_date.strftime('%d-%m-%Y'),
            mode_label,
            self.note or "N/A",
            self.env.user.name,
        ))

        # Check and auto-close
        loan._check_auto_close()
        return {'type': 'ir.actions.act_window_close'}
