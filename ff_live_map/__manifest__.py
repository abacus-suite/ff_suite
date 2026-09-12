{
    'name': 'Field Force - Live Map',
    'version': '19.0.1.9.0',
    'category': 'Human Resources/Field Force',
    'summary': 'See where every field employee is right now on a Google map inside Odoo',
    'author': 'Field Force Suite',
    'depends': ['ff_visits', 'ff_tracking', 'ff_mobile_api'],
    'data': [
        'security/ir.model.access.csv',
        'views/ff_map_usage_views.xml',
        'views/res_config_settings_views.xml',
        'views/ff_live_map_views.xml',
    ],
    'assets': {
        'web.assets_backend': [
            'ff_live_map/static/src/google.js',
            'ff_live_map/static/src/live_map.js',
            'ff_live_map/static/src/map_cost.js',
            'ff_live_map/static/src/map_cost.xml',
            'ff_live_map/static/src/live_map.xml',
            'ff_live_map/static/src/live_map.scss',
        ],
    },
    'installable': True,
    'license': 'LGPL-3',
}
