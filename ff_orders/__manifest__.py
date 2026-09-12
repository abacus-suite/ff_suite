{
    'name': 'Field Force - Orders',
    'version': '19.0.1.1.0',
    'category': 'Human Resources/Field Force',
    'summary': 'Field orders from the mobile app: SKU catalogue, geotagged orders linked to visits',
    'author': 'Field Force Suite',
    'depends': ['ff_visits', 'sale_management'],
    'data': [
        'views/product_views.xml',
        'views/sale_order_views.xml',
        'views/ff_orders_menus.xml',
    ],
    'installable': True,
    'license': 'LGPL-3',
}
