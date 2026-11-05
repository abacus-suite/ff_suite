{
    'name': 'L4E Manufacturing & Production Demand Planner',
    'version': '19.0.1.0.0',
    'category': 'Manufacturing/Manufacturing',
    'summary': 'Weekly production planning dashboard, MO suggestions, and automatic Friday draft MO generation',
    'description': """
L4E Manufacturing Demand & Production Planner
=============================================
* Dashboard in Manufacturing displaying Last Week Sales, Next Week Deliveries, Free Stock, and Suggested MO Qty.
* Suggest MO interactive wizard: pre-fills needed production, shows BOM raw materials and stock shortages, 100% editable by manager.
* Automated Friday Scheduled Action (Cron) to auto-generate draft Manufacturing Orders for the upcoming week based on sales velocity and delivery demand.
    """,
    'author': 'Krishnaraj',
    'depends': [
        'base',
        'web',
        'mrp',
        'sale_management',
        'stock',
    ],
    'data': [
        'security/ir.model.access.csv',
        'data/ir_cron_data.xml',
        'wizard/l4e_mrp_suggest_wizard_views.xml',
        'views/l4e_mrp_plan_views.xml',
        'views/l4e_mrp_menus.xml',
    ],
    'installable': True,
    'application': False,
    'license': 'LGPL-3',
}
