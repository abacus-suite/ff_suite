{
    'name': 'L4E Distributor Self-Service Portal & Email Notification',
    'version': '19.0.1.0.0',
    'category': 'Sales/Portal',
    'summary': 'Allow distributors to review, adjust quantities, and confirm orders online without Odoo login',
    'description': """
        Distributor Self-Service Portal & Email Notification
        ====================================================
        - Automatically sends an email with an order-specific portal link when a distributor quotation is created.
        - Token-based secure public portal link allows distributors to access their quotation without logging into Odoo.
        - Mobile-responsive interface for distributors to review products, adjust demanded quantities, and confirm orders.
        - Automatically updates Sale Order lines, confirms the order, and updates linked Outlet Demands.
    """,
    'author': 'Suhail ahamed',
    'license': 'LGPL-3',
    'depends': [
        'sale_management',
        'portal',
        'mail',
        'ff_demand',
    ],
    'data': [
        'data/mail_template_data.xml',
        'views/sale_order_views.xml',
        'views/ff_demand_quotation_views.xml',
        'views/distributor_portal_templates.xml',
    ],
    'installable': True,
    'application': False,
    'auto_install': False,
}
