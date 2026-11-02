# -*- coding: utf-8 -*-
{
    'name': 'L4E Product Location Routing',
    'version': '19.0.1.0.0',
    'category': 'Inventory/Purchase',
    'summary': 'Automatic stock routing for Raw materials to Storage (Godown) and Packing products to Bottling on Purchase',
    'description': """
L4E Product Location Routing
============================
- Automatically creates 4 stock locations upon module activation:
    1. Storage (Godown)
    2. Fermentation
    3. Bottling
    4. Packing
- Adds a 'Product Type' selection field in Product Master (Raw materials / Packing products).
- On Purchase Order incoming receipts (single receipt):
    - Raw materials route to 'Storage (Godown)'
    - Packing products route to 'Bottling'
    """,
    'author': 'Krishnaraj',
    'license': 'LGPL-3',
    'depends': [
        'stock',
        'purchase',
        'purchase_stock',
    ],
    'data': [
        'data/stock_location_data.xml',
        'views/product_template_views.xml',
        'views/stock_picking_views.xml',
    ],
    'post_init_hook': 'post_init_hook',
    'installable': True,
    'application': False,
    'auto_install': False,
}
