{
    'name': 'Field Force - Overtime to Compensatory Off',
    'version': '19.0.1.0.0',
    'category': 'Human Resources/Field Force',
    'summary': 'Hours worked beyond the shift become overtime the employee sends for approval; the manager may '
               'change the time, and what is approved is added to the Compensatory Off leave balance in hours',
    'author': 'Field Force Suite',
    'depends': ['ff_attendance', 'ff_leaves', 'ff_approvals'],
    'data': [
        'security/ir.model.access.csv',
        'data/ff_overtime_data.xml',
        'views/ff_overtime_views.xml',
    ],
    'installable': True,
    'auto_install': True,
    'license': 'LGPL-3',
}
