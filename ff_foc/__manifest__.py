{
    'name': 'Aixolo - FOC Schemes',
    'version': '19.0.1.0.0',
    'category': 'Human Resources/Field Force',
    'summary': 'Free-of-cost goods: buy X get Y schemes and slabs added to orders and demands, plus field FOC with a reason',
    'author': 'Field Force Suite',
    'depends': ['ff_demand', 'ff_app_reports'],
    'data': [
        'security/ir.model.access.csv',
        'views/ff_foc_views.xml',
        'views/res_config_settings_views.xml',
    ],
    'installable': True,
    'license': 'LGPL-3',
}
