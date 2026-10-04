{
    'name': 'Field Force - Contact Access Rules',
    'version': '19.0.1.0.0',
    'category': 'Human Resources/Field Force',
    'summary': 'Who sees which contacts: open, by territory, beat, city or assigned - with dated access requests',
    'description': """
City -> Territory -> Beat. A rule says how a person's contact list is worked
out; a rule for one employee beats the default rule. When somebody needs
contacts outside their list they ask their manager for a territory, beat or
city between two dates; once approved the list grows, and it shrinks back the
day after the last date.
""",
    'author': 'Field Force Suite',
    'depends': ['ff_clients', 'ff_beat', 'ff_mobile_api'],
    'data': [
        'security/ir.model.access.csv',
        'data/ff_contact_access_data.xml',
        'views/ff_territory_views.xml',
        'views/ff_contact_access_views.xml',
        'views/ff_contact_access_menus.xml',
    ],
    'installable': True,
    'license': 'LGPL-3',
}
