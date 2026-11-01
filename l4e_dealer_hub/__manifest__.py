{
    'name': 'Links4Engg Dealer Hub',
    'version': '19.0.1.0.0',
    'category': 'Human Resources/Field Force',
    'summary': 'A login portal where each distributor sees its demands, deliveries, invoices and outlet collections',
    'description': """
Distributors sign in to the Dealer Hub with a login and password that is set on
their contact. They see only their own business: the demand waiting for them,
what they have approved and delivered, what the outlets owe them and what the
field has collected for them, what they owe the company, returns and free goods.
Approving a demand and recording deliveries is done on the same pages the
e-mailed link opens.
""",
    'author': 'Field Force Suite',
    'depends': ['l4e_distributor_portal', 'ff_outlet_ledger'],
    'data': [
        'security/ir.model.access.csv',
        'wizard/dealer_hub_access_views.xml',
        'views/res_partner_views.xml',
        'views/dealer_stock_views.xml',
        'views/dealer_hub_templates.xml',
    ],
    'installable': True,
    'application': False,
    'license': 'LGPL-3',
}
