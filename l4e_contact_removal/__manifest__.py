{
    'name': 'L4E Contact Removal',
    'version': '19.0.1.0.0',
    'category': 'Sales/Contacts',
    'summary': 'Global delete option for contacts to permanently purge contact and all related database records',
    'author': 'L4E',
    'depends': ['base', 'contacts'],
    'data': [
        'security/l4e_contact_removal_security.xml',
        'security/ir.model.access.csv',
        'wizard/l4e_partner_delete_wizard_views.xml',
        'views/res_partner_views.xml',
    ],
    'installable': True,
    'application': False,
    'auto_install': False,
    'license': 'LGPL-3',
}
