# -*- coding: utf-8 -*-
from odoo import api, fields, models


class L4eLoanType(models.Model):
    _name = 'l4e.loan.type'
    _description = 'Loan Policy / Type Master'
    _order = 'name'

    name = fields.Char(string='Loan Policy Name', required=True, translate=True)
    code = fields.Char(string='Code', required=True, index=True)
    max_amount = fields.Float(
        string='Maximum Sanction Amount',
        help='Maximum permissible loan amount in ₹. Leave 0.00 for no ceiling limit.',
    )
    max_installments = fields.Integer(
        string='Maximum Tenure (Months)',
        default=12,
        help='Maximum permitted repayment installments in months.',
    )
    deduct_from_payroll = fields.Boolean(
        string='Deduct from Monthly Salary',
        default=True,
        help='Check if installments should be deducted in monthly payroll batch.',
    )
    description = fields.Text(string='Policy Terms & Conditions')
    active = fields.Boolean(default=True)
    loan_count = fields.Integer(string='Loans Count', compute='_compute_loan_count')

    def _compute_loan_count(self):
        loan_data = self.env['l4e.loan']._read_group(
            [('loan_type_id', 'in', self.ids)],
            ['loan_type_id'],
            ['__count'],
        )
        counts = {loan_type.id: count for loan_type, count in loan_data}
        for record in self:
            record.loan_count = counts.get(record.id, 0)

    def action_view_loans(self):
        self.ensure_one()
        return {
            'name': self.name,
            'type': 'ir.actions.act_window',
            'res_model': 'l4e.loan',
            'view_mode': 'list,form',
            'domain': [('loan_type_id', '=', self.id)],
            'context': {'default_loan_type_id': self.id},
        }
