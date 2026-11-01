# -*- coding: utf-8 -*-
{
    'name': 'L4E Employee Analytics',
    'version': '19.0.1.0.0',
    'category': 'Human Resources/Payroll',
    'summary': 'Automatic 1:1 synchronization between Employees and Analytic Accounts with Payroll Distribution',
    'author': 'Krishnaraj',
    'license': 'LGPL-3',
    'depends': [
        'hr',
        'analytic',
        'hr_payroll',
        'hr_payroll_account',
        'l4e_field_customization',
    ],
    'data': [
        'views/hr_employee_views.xml',
        'views/account_analytic_account_views.xml',
    ],
    'post_init_hook': 'post_init_hook',
    'installable': True,
    'application': True,
    'auto_install': False,
}
