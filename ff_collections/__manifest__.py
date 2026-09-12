{
    'name': 'Field Force - Payment Collection',
    'version': '19.0.1.0.0',
    'category': 'Human Resources/Field Force',
    'summary': 'Collect money at the customer (cash, online, cheque, PDC), deposit it to the office, '
               'with limits by amount and by days that block further check-ins',
    'author': 'Field Force Suite',
    # Depends on the API (not the other way round) so installing it never takes the API offline.
    'depends': ['ff_mobile_api'],
    'data': [
        'security/ff_collections_security.xml',
        'security/ir.model.access.csv',
        'data/ff_collections_data.xml',
        'views/ff_collection_mode_views.xml',
        'views/ff_collection_views.xml',
        'views/ff_collection_deposit_views.xml',
        'views/res_config_settings_views.xml',
        'views/ff_collections_menus.xml',
    ],
    'installable': True,
    'license': 'LGPL-3',
}
