# -*- coding: utf-8 -*-
from odoo import api, fields, models, _
from odoo.exceptions import UserError


class HrEmployee(models.Model):
    _inherit = 'hr.employee'

    analytic_account_id = fields.Many2one(
        'account.analytic.account',
        string='Analytic Account',
        readonly=True,
        copy=False,
        help="Analytic account synchronized 1:1 with this employee for payroll and cost tracking."
    )

    @api.model_create_multi
    def create(self, vals_list):
        employees = super().create(vals_list)
        for employee in employees:
            employee._sync_analytic_account()
        return employees

    def write(self, vals):
        res = super().write(vals)
        trigger_fields = {'name', 'l4e_employee_id', 'work_contact_id', 'address_home_id', 'user_id'}
        if trigger_fields & set(vals.keys()):
            for employee in self:
                employee._sync_analytic_account()
        return res

    def unlink(self):
        for employee in self:
            if employee.analytic_account_id:
                raise UserError(_(
                    "Deletion of employees with linked analytic accounts is not allowed to preserve historical records. "
                    "Please archive the employee instead."
                ))
        return super().unlink()

    def _sync_analytic_account(self):
        """
        Synchronizes 1:1 account.analytic.account for this employee.
        Naming convention: <l4e_employee_id> - <name>
        """
        self.ensure_one()
        if self.env.context.get('skip_analytic_sync'):
            return

        if not self.l4e_employee_id or not self.name:
            return

        analytic_name = f"{self.l4e_employee_id} - {self.name}"

        # Partner resolution: work_contact_id > user_id.partner_id > address_home_id
        partner = self.work_contact_id or (self.user_id.partner_id if self.user_id else False) or self.address_home_id

        # Plan resolution: 'Project' or fallback to first available active plan
        plan = self.env['account.analytic.plan'].search([('name', '=ilike', 'Project')], limit=1)
        if not plan:
            plan = self.env['account.analytic.plan'].search([], limit=1)
        if not plan:
            # Create default plan if none exists
            plan = self.env['account.analytic.plan'].create({'name': 'Default Plan'})

        # Multi-company safety
        analytic_company = self.company_id
        if partner and partner.company_id and partner.company_id != self.company_id:
            analytic_company = False

        if not self.analytic_account_id:
            # Check if an existing analytic account is already linked to this employee
            account = self.env['account.analytic.account'].search([('employee_id', '=', self.id)], limit=1)
            if not account:
                account_vals = {
                    'name': analytic_name,
                    'employee_id': self.id,
                    'company_id': analytic_company.id if analytic_company else False,
                    'plan_id': plan.id if plan else False,
                    'partner_id': partner.id if partner else False,
                }
                account = self.env['account.analytic.account'].with_context(skip_employee_sync=True).create(account_vals)
            self.with_context(skip_analytic_sync=True).write({'analytic_account_id': account.id})
        else:
            # Update existing analytic account if details changed
            account = self.analytic_account_id
            update_vals = {}
            if account.name != analytic_name:
                update_vals['name'] = analytic_name
            expected_partner_id = partner.id if partner else False
            if account.partner_id.id != expected_partner_id:
                update_vals['partner_id'] = expected_partner_id
            expected_company_id = analytic_company.id if analytic_company else False
            if account.company_id.id != expected_company_id:
                update_vals['company_id'] = expected_company_id
            if not account.employee_id or account.employee_id.id != self.id:
                update_vals['employee_id'] = self.id
            if update_vals:
                account.with_context(skip_employee_sync=True).write(update_vals)
