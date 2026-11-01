# -*- coding: utf-8 -*-
{
    'name': 'L4E Certificate Master',
    'version': '19.0.1.0.0',
    'category': 'Operations/Compliance',
    'summary': 'Certificate Master - Regulatory & Statutory Compliance Certificate Management with Automated Alerts',
    'description': """
Compliance Certificate Manager for Kumbayah Foods
=================================================
Key Features:
-------------
* Maintain all regulatory licenses and certificates (FSSAI, Factory License, Fire NOC, PCB, ISO, Water Testing, etc.)
* Track issue date, validity, and expiry dates.
* Automated daily scheduled cron job monitoring upcoming expirations.
* Tiered automated alert system:
    - 30 Days: Advance Notice Alert
    - 15 Days: Urgent Expiry Alert
    - 7 Days: Critical Expiry Alert
    - 0 Days / Expired: Expired Violation Alert
* Automated mail notifications to responsible managers and stakeholders.
* Automated Odoo Activity creation (To-Do / Call / Meeting) assigned to the certificate manager.
* Renewal tracking and certificate document upload.
* Full chatter and audit log integration.
    """,
    'author': 'Krishnaraj G V / Kumbayah Foods',
    'website': 'https://kumbayahfoods.com',
    'depends': ['base', 'mail', 'hr'],
    'data': [
        'security/compliance_security.xml',
        'security/ir.model.access.csv',
        'data/compliance_mail_template.xml',
        'data/compliance_cron.xml',
        'views/compliance_certificate_views.xml',
        'views/compliance_menu.xml',
    ],
    'installable': True,
    'application': True,
    'license': 'LGPL-3',
}
