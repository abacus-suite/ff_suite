{
    'name': 'Aixolo - Manager Alerts & Email Digest',
    'version': '19.0.1.0.0',
    'category': 'Human Resources/Field Force',
    'summary': 'Tell managers when someone stops moving, loses signal, turns GPS off or visits offsite; daily and weekly email summary',
    'author': 'Field Force Suite',
    'depends': ['ff_approvals', 'ff_visits', 'ff_tracking'],
    'data': [
        'security/ir.model.access.csv',
        'data/ff_alerts_cron.xml',
        'views/ff_alert_views.xml',
        'views/res_config_settings_views.xml',
    ],
    'installable': True,
    'license': 'LGPL-3',
}
