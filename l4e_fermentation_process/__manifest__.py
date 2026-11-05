# -*- coding: utf-8 -*-
{
    'name': 'Fermentation Process & Quality Management',
    'version': '19.0.1.0.0',
    'category': 'Manufacturing/Manufacturing',
    'summary': 'Fermentation Process, 52 Tanks Management, Internal Transfers, and 15th-Day Quality Checks for Kumbayah Foods',
    'description': """
Fermentation Process & Quality Management
=========================================
Manages the fermentation stage of Kombucha production:
* Management of the 52 Fermentation Tanks with real-time status (Available / Occupied)
* Internal Transfer from Brewing / Godown to Fermentation location
* Tracking of Preparation Date, Transfer Date, and 15th-Day Quality Check Due Date
* 15th-Day Quality Check tab with customizable parameters and Pass / Fail badges
* Integration with Brewing Tea Master via one-click transfer wizard
* Full audit trail and chatter integration
    """,
    'author': 'Kumbayah Foods',
    'website': 'https://kumbayahfoods.com',
    'license': 'LGPL-3',
    'depends': [
        'base',
        'mail',
        'mrp',
        'stock',
        'l4e_product_location',
        'l4e_brewing_tea',
    ],
    'data': [
        'security/fermentation_security.xml',
        'security/ir.model.access.csv',
        'data/fermentation_sequence.xml',
        'data/fermentation_tank_data.xml',
        'wizard/fermentation_transfer_wizard_views.xml',
        'views/fermentation_tank_views.xml',
        'views/fermentation_process_views.xml',
        'views/brewing_tea_inherit_views.xml',
        'views/fermentation_menus.xml',
    ],
    'installable': True,
    'application': False,
    'auto_install': False,
}
