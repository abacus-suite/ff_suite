{
    'name': 'Field Force - Live Map',
    'version': '19.0.1.0.0',
    'category': 'Human Resources/Field Force',
    'summary': 'See where every field employee is right now on a Google map inside Odoo',
    'author': 'Field Force Suite',
    'depends': ['ff_visits', 'ff_tracking'],
    'data': [
        'views/ff_live_map_views.xml',
    ],
    'assets': {
        'web.assets_backend': [
            'ff_live_map/static/src/live_map.js',
            'ff_live_map/static/src/live_map.xml',
            'ff_live_map/static/src/live_map.scss',
        ],
    },
    'installable': True,
    'license': 'LGPL-3',
}
