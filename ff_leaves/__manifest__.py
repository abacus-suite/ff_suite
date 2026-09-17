{
    'name': 'Field Force - Leaves in the App',
    'version': '19.0.1.0.1',
    'category': 'Human Resources/Field Force',
    'summary': "Request time off from the phone and approve it there, on Odoo's own Time Off",
    'author': 'Field Force Suite',
    'depends': ['ff_mobile_api', 'hr_holidays'],
    'data': [
        'views/hr_leave_type_views.xml',
        'views/ff_leaves_menus.xml',
    ],
    'installable': True,
    'license': 'LGPL-3',
}
