{
    'name': 'Aixolo - Tasks',
    'version': '19.0.1.0.1',
    'category': 'Human Resources/Field Force',
    'summary': 'Tasks assigned to field staff, done and proven from the app',
    'author': 'Field Force Suite',
    'depends': ['ff_app_reports'],
    'data': [
        'security/ir.model.access.csv',
        'views/ff_task_views.xml',
    ],
    'installable': True,
    'license': 'LGPL-3',
}
