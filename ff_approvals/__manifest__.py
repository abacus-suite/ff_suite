{
    'name': 'Field Force - Approval Chains & Notifications',
    'version': '19.0.1.0.0',
    'category': 'Human Resources/Field Force',
    'summary': 'First approver, second approver, and everybody told - in Odoo and in the app',
    'author': 'Field Force Suite',
    'depends': ['ff_mobile_api', 'ff_expenses', 'ff_allowance'],
    'data': [
        'security/ir.model.access.csv',
        'security/ff_approvals_security.xml',
        'views/ff_approval_flow_views.xml',
        'views/ff_notification_views.xml',
        'views/ff_claim_views.xml',
        'views/ff_approvals_menus.xml',
    ],
    'installable': True,
    'license': 'LGPL-3',
}
