{
    'name': 'Aixolo - Returns & Damaged Stock',
    'version': '19.0.1.0.0',
    'category': 'Human Resources/Field Force',
    'summary': 'Sales returns and damaged or expired stock reported at the outlet, approved, and credited',
    'author': 'Field Force Suite',
    'depends': ['ff_approvals', 'ff_app_reports', 'account'],
    'data': [
        'security/ir.model.access.csv',
        'data/ff_return_sequence.xml',
        'views/ff_return_views.xml',
    ],
    'installable': True,
    'license': 'LGPL-3',
}
