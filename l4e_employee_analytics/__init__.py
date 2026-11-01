# -*- coding: utf-8 -*-
from . import models


def post_init_hook(env):
    """
    Automatically generate and link analytic accounts for existing employees
    with l4e_employee_id upon module installation.
    """
    employees = env['hr.employee'].search([
        ('l4e_employee_id', '!=', False),
        ('analytic_account_id', '=', False),
    ])
    for employee in employees:
        employee._sync_analytic_account()
