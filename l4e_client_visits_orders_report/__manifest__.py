{
    'name': 'Field Force - Client Visits & Associated Orders Report',
    'version': '19.0.1.0.0',
    'category': 'Human Resources/Field Force',
    'summary': 'Client Visits & Associated Orders Worked PDF Report with SKU details and photos',
    'description': """
Client Visits & Associated Orders Report
========================================
* Multi-column landscape report linking Visits to placed Orders / Demands.
* Displays Task UUID, Client, Task Description, SKU Name, Quantity, SKU Cases breakdown, Photos, Start/End/Exit times, and Team.
* Filter by Date Range, Team, and one or multiple Employees.
    """,
    'author': 'Links4Engineers',
    'depends': [
        'base',
        'web',
        'hr',
        'ff_base',
        'ff_visits',
        'ff_orders',
        'ff_demand',
        'l4e_weekly_chiller_report',
    ],
    'data': [
        'security/ir.model.access.csv',
        'report/visits_orders_report_templates.xml',
        'wizard/visits_orders_report_wizard_views.xml',
        'views/ff_reporting_menus.xml',
    ],
    'installable': True,
    'application': False,
    'license': 'LGPL-3',
}
