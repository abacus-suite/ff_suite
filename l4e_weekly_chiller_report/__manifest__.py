{
    'name': 'Field Force - Reports (Chiller & Daily Visits)',
    'version': '19.0.1.1.0',
    'category': 'Human Resources/Field Force',
    'summary': 'Weekly Chiller Update & Daily Visit PDF Reports with filter wizards and photos',
    'description': """
Field Force Reports Suite
=========================
* Adds Reporting menu under Field Force top navigation bar.
* Weekly Chiller Update Report: Formatted PDF report with chiller verification photos.
* Daily Visit Report: 11-column landscape PDF report with client, task, side-by-side photos, start/end/exit times, territory, and city.
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
        'report/daily_visit_report_templates.xml',
        'wizard/weekly_chiller_report_wizard_views.xml',
        'wizard/daily_visit_report_wizard_views.xml',
        'views/ff_reporting_menus.xml',
    ],
    'installable': True,
    'application': False,
    'license': 'LGPL-3',
}
