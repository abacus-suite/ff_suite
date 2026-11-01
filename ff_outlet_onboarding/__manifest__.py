{
    'name': 'Field Force - Outlet & Distributor Onboarding',
    'version': '19.0.1.1.0',
    'category': 'Human Resources/Field Force',
    'summary': 'Turn a lead into an outlet or distributor with the GST, contact, MRP, Swiggy/Zomato and chiller '
               'details the client requires',
    'author': 'Field Force Suite',
    'depends': ['ff_visit_tasks', 'ff_demand', 'ff_clients', 'ff_mobile_api'],
    'data': [
        'security/ir.model.access.csv',
        'data/ff_partner_option_data.xml',
        'views/res_partner_views.xml',
        'views/hr_employee_views.xml',
        'views/res_config_settings_views.xml',
        'views/ff_partner_option_views.xml',
    ],
    'installable': True,
    'license': 'LGPL-3',
}
