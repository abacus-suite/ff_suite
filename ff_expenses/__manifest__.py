{
    'name': 'Field Force - Expenses',
    'version': '19.0.1.0.0',
    'category': 'Human Resources/Field Force',
    'summary': 'Field expense claims with receipt photos, expense types per department and manager approval',
    'author': 'Field Force Suite',
    # Depends on the API (not the other way round) so installing it never takes the API offline.
    'depends': ['ff_mobile_api'],
    'data': [
        'security/ff_expenses_security.xml',
        'security/ir.model.access.csv',
        'data/ff_expenses_data.xml',
        'views/ff_expense_category_views.xml',
        'views/ff_expense_claim_views.xml',
        'views/ff_expenses_menus.xml',
    ],
    'installable': True,
    'license': 'LGPL-3',
}
