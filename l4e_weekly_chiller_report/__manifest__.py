{
    'name': 'Field Force - Weekly Chiller Update Report',
    'version': '19.0.1.0.0',
    'category': 'Human Resources/Field Force',
    'summary': 'Weekly Chiller Task PDF Report with filter wizard and chiller photos',
    'description': """
Field Force Weekly Chiller Update Report
========================================
* Adds Reporting menu under Field Force top navigation bar.
* Wizard to filter by Date Range, Team, and one or multiple Employees.
* Prints formatted PDF report with embedded chiller photos matching field specifications.
    """,
    'author': 'Links4Engineers',
    'depends': [
        'base',
        'web',
        'hr',
        'ff_base',
        'ff_visits',
    ],
    'data': [
        'security/ir.model.access.csv',
        'report/weekly_chiller_report_templates.xml',
        'wizard/weekly_chiller_report_wizard_views.xml',
        'views/ff_reporting_menus.xml',
    ],
    'installable': True,
    'application': False,
    'license': 'LGPL-3',
}
