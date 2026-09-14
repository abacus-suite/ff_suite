{
    'name': 'Field Force - Targets',
    'version': '19.0.2.1.0',
    'category': 'Human Resources/Field Force',
    'summary': 'Monthly visit, customer, sales and collection targets per employee, with achievement',
    'author': 'Field Force Suite',
    'depends': ['ff_dashboard'],
    'data': [
        'security/ir.model.access.csv',
        'views/ff_target_views.xml',
        'views/res_config_settings_views.xml',
    ],
    'installable': True,
    'license': 'LGPL-3',
}
