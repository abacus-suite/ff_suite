# -*- coding: utf-8 -*-
from odoo import api, fields, models, _
from odoo.exceptions import UserError


class L4eLoanInstallment(models.Model):
    _name = 'l4e.loan.installment'
    _description = 'Loan Repayment Installment Schedule'
    _order = 'loan_id, sequence, date'

    name = fields.Char(string='Installment No.', required=True)
    sequence = fields.Integer(string='Sequence', default=10)
    loan_id = fields.Many2one(
        'l4e.loan',
        string='Loan Reference',
        required=True,
        ondelete='cascade',
        index=True,
    )
    loan_type_id = fields.Many2one(
        'l4e.loan.type',
        related='loan_id.loan_type_id',
        string='Loan Type',
        store=True,
    )
    employee_id = fields.Many2one(
        'hr.employee',
        related='loan_id.employee_id',
        string='Employee',
        store=True,
        index=True,
    )
    company_id = fields.Many2one(
        'res.company',
        related='loan_id.company_id',
        string='Company',
        store=True,
    )
    currency_id = fields.Many2one(
        'res.currency',
        related='loan_id.currency_id',
        string='Currency',
    )
    date = fields.Date(
        string='Due Date',
        required=True,
        index=True,
        help='Scheduled salary deduction date for this installment.',
    )
    amount = fields.Monetary(
        string='Installment Amount',
        required=True,
        help='Monthly repayment amount to deduct from salary.',
    )
    state = fields.Selection([
        ('pending', 'Pending'),
        ('paid', 'Paid'),
        ('overdue', 'Overdue / Skipped'),
    ], string='Status', default='pending', required=True, index=True)

    is_paid = fields.Boolean(
        string='Is Paid',
        compute='_compute_is_paid',
        store=True,
    )
    paid_date = fields.Date(
        string='Paid Date',
        readonly=True,
        help='Date when this installment was deducted or received.',
    )
    payslip_ref = fields.Char(
        string='Payslip / Batch Ref',
        help='Reference of monthly payroll batch or payslip deduction.',
    )
    note = fields.Char(string='Notes / Reference')

    @api.depends('state')
    def _compute_is_paid(self):
        for rec in self:
            rec.is_paid = (rec.state == 'paid')

    def action_mark_paid(self, paid_date=None, payslip_ref=None):
        """Mark installment as deducted/paid and verify if parent loan is now cleared."""
        effective_date = paid_date or fields.Date.context_today(self)
        for rec in self:
            if rec.loan_id.state not in ('disbursed', 'closed'):
                raise UserError(_("Cannot mark installments as paid until the loan is Disbursed / Active."))
            rec.write({
                'state': 'paid',
                'paid_date': effective_date,
                'payslip_ref': payslip_ref or rec.payslip_ref or False,
            })
            # Log in parent loan chatter
            rec.loan_id.message_post(
                body=_("<b>✔️ Installment Paid:</b> %s of ₹ %s on %s.") % (
                    rec.name, "{:,.2f}".format(rec.amount), effective_date.strftime('%d-%m-%Y')
                ),
                subtype_xmlid='mail.mt_note',
            )
            # Recheck parent loan balance and auto-close if ₹0.00
            rec.loan_id._check_auto_close()
        return True

    def action_mark_overdue(self):
        """Flag installment as skipped/overdue (e.g. insufficient salary)."""
        for rec in self:
            rec.write({'state': 'overdue'})
            rec.loan_id.message_post(
                body=_("<b>⚠️ Installment Skipped / Overdue (OD):</b> %s of ₹ %s was not deducted on %s.") % (
                    rec.name, "{:,.2f}".format(rec.amount), rec.date.strftime('%d-%m-%Y') if rec.date else ''
                ),
                subtype_xmlid='mail.mt_note',
            )
        return True

    def action_reset_pending(self):
        """Reset installment back to pending."""
        for rec in self:
            rec.write({
                'state': 'pending',
                'paid_date': False,
            })
            rec.loan_id._check_auto_close()
        return True
