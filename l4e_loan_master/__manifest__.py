# -*- coding: utf-8 -*-
{
    'name': 'L4E Employee Loan & Advance Master',
    'version': '19.0.1.0.0',
    'category': 'Human Resources/Employees',
    'summary': 'Manage employee loans, salary advances, E-Bike deduction schemes, amortization schedules, and historical records',
    'description': """
L4E Employee Loan & Advance Master
==================================
Kumbayah Foods - Task 8.02 of Master SOW

Features:
- Dedicated Loan Policy / Type Master (Salary Advance, E-Bike Scheme, Festival Loan, Personal Loan)
- Complete Application & Approval Workflow (Draft -> Submitted -> Approved -> Disbursed -> Closed)
- Auto-calculated Monthly Repayment Schedules with exact paisa rounding
- Standalone manual and bulk installment tracking (ready for automated Payroll integration in Task 8.03/8.07)
- Historical & Opening Balance Migration (migrating existing loans from Tally/Excel with partial recovery)
- Overdue (OD) & Skipped Installment Tracking
- Employee Lifetime Credit Profile and Reliability Rating
- Pre-closure / Early Settlement wizard
- Smart Button on Employee profile
    """,
    'author': 'Suhail Ahamed A',
    'license': 'LGPL-3',
    'depends': [
        'base',
        'hr',
        'mail',
    ],
    'data': [
        'security/security.xml',
        'security/ir.model.access.csv',
        'data/ir_sequence_data.xml',
        'data/l4e_loan_type_data.xml',
        'wizard/l4e_loan_settle_wizard_views.xml',
        'views/l4e_loan_type_views.xml',
        'views/l4e_loan_installment_views.xml',
        'views/l4e_loan_views.xml',
        'views/hr_employee_views.xml',
        'views/l4e_loan_menus.xml',
    ],
    'installable': True,
    'application': True,
    'auto_install': False,
}
