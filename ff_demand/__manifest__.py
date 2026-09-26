{
    'name': 'Field Force - Demand & Distributor Quotations',
    'version': '19.0.1.1.4',
    'category': 'Human Resources/Field Force',
    'summary': 'Collect demand at the outlet, consolidate it per distributor, quote the distributor',
    'author': 'Field Force Suite',
    'depends': ['ff_mobile_api', 'ff_orders', 'ff_beat'],
    'data': [
        'security/ir.model.access.csv',
        'security/ff_demand_security.xml',
        'data/ff_demand_data.xml',
        # The wizard action is referenced by the demand form, so it loads first.
        'wizard/ff_demand_quotation_views.xml',
        'views/ff_demand_views.xml',
        'views/res_partner_views.xml',
        'views/sale_order_views.xml',
        'views/res_config_settings_views.xml',
        'views/ff_demand_menus.xml',
    ],
    'installable': True,
    'license': 'LGPL-3',
}
