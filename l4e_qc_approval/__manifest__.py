# -*- coding: utf-8 -*-
{
    'name': 'L4E Quality Control & Approval Management',
    'version': '19.0.1.0.0',
    'category': 'Manufacturing/Quality',
    'summary': 'QC Test Master with Min/Max Tolerances, Out-of-Range Detection, and QC Manager Approval Workflows',
    'description': """
L4E Quality Control & Approval Management
=========================================
Adds centralized Quality Control Master and manager deviation sign-off across Kumbayah Manufacturing:

1. **QC Approval Master (qc.test.parameter)**:
   - Configure test names (pH, Brix/Sugar, Temperature, Taste, Color, etc.).
   - Define test types: Numeric Range (with Minimum / Maximum thresholds) and Sensory/Qualitative (Pass/Fail).
   - Set measurement units and process applicability (Brewing, Fermentation, Mixing, or All).

2. **Integration across Operations**:
   - **Brewing Tea**: QC lines dropdown to standard tests with auto-evaluation against Min/Max.
   - **Fermentation**: Day-15 QC checklist with threshold checking.
   - **Mixing Process**: 1st QC (Pre-mixing) and 2nd QC (Post-mixing) lines integrated.

3. **Deviation & Approval Workflow**:
   - Out-of-range readings display a **"Request QC Approval"** button.
   - Submits deviation to the **QC Manager** group with scheduled activity.
   - QC Manager reviews and can **Approve (Override)** or **Reject**.
   - Downstream actions (Transfer to Fermentation, Ready for Bottling, Complete to Packing) remain blocked until approved.
    """,
    'author': 'Kumbayah Foods',
    'website': 'https://kumbayahfoods.com',
    'license': 'LGPL-3',
    'depends': [
        'base',
        'mail',
        'mrp',
        'l4e_brewing_tea',
        'l4e_fermentation_process',
        'l4e_mixing_process',
    ],
    'data': [
        'security/qc_approval_security.xml',
        'security/ir.model.access.csv',
        'data/qc_test_parameter_data.xml',
        'views/qc_test_parameter_views.xml',
        'views/brewing_tea_qc_views.xml',
        'views/fermentation_qc_views.xml',
        'views/mixing_qc_views.xml',
        'views/qc_approval_menus.xml',
    ],
    'installable': True,
    'application': False,
    'auto_install': False,
}
