{
    'name': 'L4E Field Customization',
    'version': '19.0.1.6.0',
    'category': 'Human Resources',
    'summary': 'Custom fields for Employee and Contact masters — Kumbayah Foods',
    'author': 'Krishnaraj',
    'depends': ['hr', 'base', 'account', 'product', 'ff_clients', 'ff_beat'],
    'data': [
        'security/ir.model.access.csv',
        'data/master_data.xml',
        'views/hr_employee_views.xml',
        'views/res_partner_views.xml',
    ],
    'installable': True,
    'application': False,
    'auto_install': False,
    'license': 'LGPL-3',
}
