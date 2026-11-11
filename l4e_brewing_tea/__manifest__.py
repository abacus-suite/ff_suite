# -*- coding: utf-8 -*-
{
    'name': 'Brewing Tea Master',
    'version': '19.0.1.0.0',
    'category': 'Manufacturing/Manufacturing',
    'summary': 'Brewing Tea Master with Preparation Tracking and Quality Checks for Kumbayah Foods',
    'description': """
Brewing Tea Master
==================
Custom master for Brewing Tea operations in the Manufacturing module:
* SI No (Serial / Batch sequence number: BT/YYYY/XXXX)
* Preparation Date tracking
* Product selection (defaults to Brewed Tea)
* Quantity produced / brewed tracked in Litres (L)
* Automatic stock entry into Storage (Godown) on passed Quality Check
* Quality Check tab with customizable checklist lines
* Full chatter and audit trail integration
    """,
    'author': 'Kumbayah Foods',
    'website': 'https://kumbayahfoods.com',
    'depends': ['base', 'mail', 'mrp', 'stock'],
    'data': [
        'security/brewing_tea_security.xml',
        'security/ir.model.access.csv',
        'data/brewing_tea_sequence.xml',
        'data/brewing_tea_product_data.xml',
        'views/brewing_tea_views.xml',
        'views/brewing_tea_menus.xml',
    ],
    'installable': True,
    'application': False,
    'license': 'LGPL-3',
}
