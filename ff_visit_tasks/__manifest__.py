{
    'name': 'Field Force - Sales Staff Tasks',
    'version': '19.0.1.0.0',
    'category': 'Human Resources/Field Force',
    'summary': 'Client visit, new lead, follow up, adhoc, sample collection and marketing material '
               'supply: what each task captures, step by step, and a report of them all',
    'description': """
Six tasks the sales staff perform, each a fixed sequence of screens in the app.
This holds what they capture and everything they set going: the stock count, the
demand and its free quantity, the credit and debit notes, the marketing material
at each outlet and the lead's next visit.

Products are listed by category: a category marked Tracking Needed is the
flavours counted and ordered, one marked Marketing Material is the material.
""",
    'author': 'Field Force Suite',
    'depends': ['ff_demand', 'ff_outlet_ledger', 'ff_visit_steps', 'ff_foc', 'ff_beat'],
    'data': [
        'security/ir.model.access.csv',
        'security/ff_visit_tasks_security.xml',
        'data/ff_visit_tasks_data.xml',
        'data/ff_marketing_material_data.xml',
        'views/ff_task_type_views.xml',
        'views/ff_task_log_views.xml',
        'views/ff_distributor_note_views.xml',
        'views/ff_partner_material_views.xml',
        'views/product_category_views.xml',
        'views/ff_visit_tasks_menus.xml',
    ],
    'installable': True,
    'license': 'LGPL-3',
}
