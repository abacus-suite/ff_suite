{
    'name': 'Field Force - Travel Allowance',
    'version': '19.0.1.0.0',
    'category': 'Human Resources/Field Force',
    'summary': 'Daily petrol / travel allowance by policy: GPS, client-to-client, route-to-route or fixed',
    'author': 'Field Force Suite',
    'depends': ['ff_beat'],
    'data': [
        'security/ff_allowance_security.xml',
        'security/ir.model.access.csv',
        'data/ff_allowance_cron.xml',
        'views/ff_allowance_policy_views.xml',
        'views/ff_allowance_claim_views.xml',
        'views/hr_employee_views.xml',
        'views/ff_allowance_menus.xml',
    ],
    'installable': True,
    'license': 'LGPL-3',
}
