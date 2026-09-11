{
    'name': 'Field Force - Beat Plans',
    'version': '19.0.1.0.0',
    'category': 'Human Resources/Field Force',
    'summary': 'Beat routes, daily beat plans, completion and distance deviation',
    'author': 'Field Force Suite',
    'depends': ['ff_visits', 'ff_attendance'],
    'data': [
        'security/ff_beat_security.xml',
        'security/ir.model.access.csv',
        'wizard/ff_beat_assign_wizard_views.xml',
        'views/ff_beat_views.xml',
        'views/ff_beat_plan_views.xml',
        'views/ff_beat_menus.xml',
    ],
    'installable': True,
    'license': 'LGPL-3',
}
