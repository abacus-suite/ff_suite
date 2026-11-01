# -*- coding: utf-8 -*-
from odoo import api, fields, models, _


class HrEmployee(models.Model):
    _inherit = 'hr.employee'

    loan_ids = fields.One2many(
        'l4e.loan',
        'employee_id',
        string='Loans & Advances',
    )
    loan_count = fields.Integer(
        string='Total Loans Count',
        compute='_compute_loan_stats',
    )
    active_loan_count = fields.Integer(
        string='Active Loans Count',
        compute='_compute_loan_stats',
    )
    total_loan_balance = fields.Monetary(
        string='Active Loan Exposure (₹)',
        compute='_compute_loan_stats',
        currency_field='currency_id',
    )

    def _compute_loan_stats(self):
        for emp in self:
            loans = emp.loan_ids
            active_loans = loans.filtered(lambda l: l.state == 'disbursed')
            emp.loan_count = len(loans)
            emp.active_loan_count = len(active_loans)
            emp.total_loan_balance = sum(active_loans.mapped('balance_amount'))

    def action_view_loans(self):
        self.ensure_one()
        return {
            'name': _("Loans: %s") % self.name,
            'type': 'ir.actions.act_window',
            'res_model': 'l4e.loan',
            'view_mode': 'list,form',
            'domain': [('employee_id', '=', self.id)],
            'context': {
                'default_employee_id': self.id,
                'search_default_employee_id': self.id,
            },
        }
