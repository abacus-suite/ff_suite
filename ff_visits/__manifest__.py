{
    'name': 'Field Force - Client Visits',
    'version': '19.0.1.0.0',
    'category': 'Human Resources/Field Force',
    'summary': 'Geofence-verified client check-in / check-out with photos and outcome',
    'author': 'Field Force Suite',
    'depends': ['ff_clients', 'ff_tracking'],
    'data': [
        'security/ff_visits_security.xml',
        'security/ir.model.access.csv',
        'data/ff_visits_cron.xml',
        'views/ff_visit_views.xml',
        'views/res_partner_views.xml',
        'views/ff_visits_menus.xml',
    ],
    'installable': True,
    'license': 'LGPL-3',
}
