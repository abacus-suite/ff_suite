# -*- coding: utf-8 -*-
{
    'name': 'Mixing Process & Quality Control',
    'version': '19.0.1.0.0',
    'category': 'Manufacturing/Manufacturing',
    'summary': 'Mixing Process, Mixing Area Location, 2-Stage Quality Checks, and Draft Packing Transfer for Kumbayah Foods',
    'description': """
Mixing Process & Quality Control
================================
* Automatically routes completed Manufacturing Order (MO) output to the 'Mixing Area' location.
* Creates a Mixing Process record in Draft stage upon clicking 'Produce All' in MO.
* Two-step Quality Control with pH value and Pass/Fail verification:
  - 1st QC Check (Pre-Mixing): becomes read-only once verified.
  - 2nd QC Check (Post-Mixing): verifies mixing quality.
* Once 2nd QC is verified, the 'Done' button appears.
* Clicking 'Done' creates a draft Internal Transfer from Mixing Area to Packing location.
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
    ],
    'data': [
        'security/mixing_security.xml',
        'security/ir.model.access.csv',
        'data/stock_location_data.xml',
        'data/mixing_sequence.xml',
        'views/mixing_process_views.xml',
        'views/mrp_production_views.xml',
        'views/mixing_menus.xml',
    ],
    'installable': True,
    'application': False,
    'auto_install': False,
}
