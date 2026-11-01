# -*- coding: utf-8 -*-
from odoo import models


class HrPayslip(models.Model):
    _inherit = 'hr.payslip'

    def _prepare_line_values(self, line, account_id, date, debit, credit):
        res = super()._prepare_line_values(line, account_id, date, debit, credit)
        employee = line.slip_id.employee_id
        employee_analytic = employee.analytic_account_id

        def _apply_custom_values(line_dict):
            if not line_dict.get('analytic_distribution') and employee_analytic:
                line_dict['analytic_distribution'] = {str(employee_analytic.id): 100}
            if line.code == 'NET' and employee.work_contact_id:
                line_dict['partner_id'] = employee.work_contact_id.id

        if isinstance(res, list):
            for item in res:
                _apply_custom_values(item)
        elif isinstance(res, dict):
            _apply_custom_values(res)

        return res
