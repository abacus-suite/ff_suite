{
    'name': 'Field Force - Panel & Dashboard',
    'version': '19.0.3.22.0',
    'category': 'Human Resources/Field Force',
    'summary': 'The Field Force panel: a sidebar workspace whose first screen is the realtime dashboard',
    'author': 'Field Force Suite',
    'depends': ['ff_mobile_api', 'ff_live_map', 'ff_app_reports'],
    'data': [
        'views/ff_panel_views.xml',
    ],
    'assets': {
        'web.assets_backend': [
            'ff_dashboard/static/src/chart.js',
            'ff_dashboard/static/src/chart.xml',
            'ff_dashboard/static/src/panel.js',
            'ff_dashboard/static/src/panel.xml',
            'ff_dashboard/static/src/panel.scss',
        ],
    },
    'installable': True,
    'license': 'LGPL-3',
}
