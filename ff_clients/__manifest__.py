{
    'name': 'Field Force - Clients',
    'version': '19.0.1.2.2',
    'category': 'Human Resources/Field Force',
    'summary': 'Field contacts with categories per department, country/state/district, GPS geofence and approval',
    'author': 'Field Force Suite',
    'depends': ['ff_base', 'contacts'],
    'data': [
        'security/ir.model.access.csv',
        'data/ff_clients_data.xml',
        'views/ff_contact_category_views.xml',
        'views/ff_district_views.xml',
        'views/res_partner_views.xml',
        'views/ff_clients_menus.xml',
    ],
    'installable': True,
    'license': 'LGPL-3',
}
