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
* Quantity produced / brewed
* Quality Check tab with customizable checklist lines:
  - SI No
  - Description
  - Pass / Fail selection with color badge widget (Pass = Green, Fail = Red)
* Automatic QC Status determination (Pass / Fail) based on check results
* Full chatter and audit trail integration
    """,
    'author': 'Kumbayah Foods',
    'website': 'https://kumbayahfoods.com',
    'depends': ['base', 'mail', 'mrp'],
    'data': [
        'security/brewing_tea_security.xml',
        'security/ir.model.access.csv',
        'data/brewing_tea_sequence.xml',
        'views/brewing_tea_views.xml',
        'views/brewing_tea_menus.xml',
    ],
    'installable': True,
    'application': False,
    'license': 'LGPL-3',
}
