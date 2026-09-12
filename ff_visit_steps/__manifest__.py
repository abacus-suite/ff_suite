{
    'name': 'Field Force - Visit Steps & Stock Count',
    'version': '19.0.1.0.1',
    'category': 'Human Resources/Field Force',
    'summary': 'Guided visit steps (notes, photo, form, stock count, order, payment) and stock counting with history',
    'author': 'Field Force Suite',
    # Depends on the API (not the other way round) so installing it never takes the API offline.
    'depends': ['ff_forms'],
    'data': [
        'security/ff_visit_steps_security.xml',
        'security/ir.model.access.csv',
        'data/ff_visit_steps_data.xml',
        'views/ff_visit_step_views.xml',
        'views/ff_stock_count_views.xml',
        'views/ff_visit_views.xml',
        'views/ff_visit_steps_menus.xml',
    ],
    'installable': True,
    'license': 'LGPL-3',
}
