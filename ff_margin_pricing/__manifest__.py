{
    'name': 'Field Force - Margin Pricing',
    'version': '19.0.1.0.0',
    'category': 'Human Resources/Field Force',
    'summary': 'Price demands and orders from MRP less the margin % of the contact, and settle any margin '
               'offered above the company margin with a debit note',
    'description': """
Two ways to price, chosen in the settings:

* **Product prices**: each product carries its own PTS and PTR (as before).
* **Margin %**: the product carries only its MRP. An outlet is priced at MRP less its own
  margin %, and a distributor at MRP less the company's total margin %.

The company has one total margin (say 30%) to share between the distributor and the outlet.
When the margins agreed at onboarding add up to more (say 20% + 12% = 32%), the extra 2% is
the company's cost: a debit note for that distributor is raised on every delivery, so the
distributor is made whole and the books tally.
""",
    'author': 'Field Force Suite',
    'depends': ['ff_outlet_onboarding', 'ff_outlet_ledger', 'ff_orders', 'ff_demand', 'ff_visit_tasks'],
    'data': [
        'security/ir.model.access.csv',
        'views/res_config_settings_views.xml',
        'views/ff_demand_views.xml',
        'views/ff_distributor_note_views.xml',
    ],
    'installable': True,
    'license': 'LGPL-3',
}
