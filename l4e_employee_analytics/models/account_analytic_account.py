# -*- coding: utf-8 -*-
from odoo import api, fields, models, _
from odoo.exceptions import UserError


class AccountAnalyticAccount(models.Model):
    _inherit = 'account.analytic.account'

    employee_id = fields.Many2one(
        'hr.employee',
        string='Employee',
        readonly=True,
        copy=False,
        help="Employee linked 1:1 with this analytic account."
    )

    @api.model_create_multi
    def create(self, vals_list):
        accounts = super().create(vals_list)
        if not self.env.context.get('skip_employee_sync'):
            for account in accounts:
                if account.employee_id and account.employee_id.analytic_account_id != account:
                    account.employee_id.with_context(skip_analytic_sync=True).write({
                        'analytic_account_id': account.id
                    })
        return accounts

    def write(self, vals):
        res = super().write(vals)
        if not self.env.context.get('skip_employee_sync'):
            for account in self:
                if account.employee_id and account.employee_id.analytic_account_id != account:
                    account.employee_id.with_context(skip_analytic_sync=True).write({
                        'analytic_account_id': account.id
                    })
        return res

    def unlink(self):
        for account in self:
            if account.employee_id:
                raise UserError(_(
                    "Deletion of analytic accounts linked to employees is not allowed to preserve historical records."
                ))
        return super().unlink()
