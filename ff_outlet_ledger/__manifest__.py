{
    'name': 'Field Force - Outlet Invoices & Payments',
    'version': '19.0.1.0.0',
    'category': 'Human Resources/Field Force',
    'summary': 'What outlets owe their distributors, what the field collected for them, and what '
               'each distributor has earned - kept apart from the company accounts',
    'description': """
A distributor sells to its outlets on its own invoices, and the company has no
part in that money. It still needs to know how much has been collected for each
distributor, how much is pending and what the distributor has earned from it,
so those invoices and payments are kept here and not in Accounting.

Money a distributor pays the company is a different thing: those are ordinary
Odoo invoices and payments, and the collections screen ties them to the
company's invoices in Accounting.
""",
    'author': 'Field Force Suite',
    'depends': ['ff_collections', 'ff_demand'],
    'data': [
        'security/ir.model.access.csv',
        'security/ff_outlet_ledger_security.xml',
        'data/ff_outlet_ledger_data.xml',
        'views/ff_outlet_invoice_views.xml',
        'views/ff_outlet_payment_views.xml',
        'views/res_partner_views.xml',
        'views/ff_outlet_ledger_menus.xml',
    ],
    'installable': True,
    'license': 'LGPL-3',
}
