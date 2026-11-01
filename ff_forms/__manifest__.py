{
    'name': 'Field Force - Form Builder',
    'version': '19.0.1.1.0',
    'category': 'Human Resources/Field Force',
    'summary': 'No-code forms for field staff: surveys, audits, contact profiles, mandatory visit checklists',
    'author': 'Field Force Suite',
    # Depends on the API (not the other way round) so installing it can never take the API offline.
    'depends': ['ff_mobile_api'],
    'data': [
        'security/ff_forms_security.xml',
        'security/ir.model.access.csv',
        'views/ff_form_views.xml',
        'views/ff_form_response_views.xml',
        'views/ff_forms_menus.xml',
    ],
    'installable': True,
    'license': 'LGPL-3',
}
