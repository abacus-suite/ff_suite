{
    'name': 'Field Force - Employee Attribution',
    'version': '19.0.1.0.0',
    'category': 'Human Resources/Field Force',
    'summary': 'Stamp the field employee, team and route on business documents so every '
               'order, lead, invoice, payment and expense can be credited to the person behind it',
    'author': 'Field Force Suite',
    'depends': ['ff_beat', 'ff_orders', 'ff_expenses'],
    'data': [
        'views/sale_order_views.xml',
        'views/res_partner_views.xml',
        'views/ff_expense_claim_views.xml',
    ],
    'installable': True,
    'license': 'LGPL-3',
}
