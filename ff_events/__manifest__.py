{
    'name': 'Field Force - Events',
    'version': '19.0.1.0.0',
    'category': 'Human Resources/Field Force',
    'summary': 'Sampling and sales events run by the field team: stock by distributor, end of day, '
               'end of event and the event report',
    'author': 'Field Force Suite',
    'depends': ['ff_visit_tasks', 'ff_contact_access', 'ff_mobile_api', 'ff_app_reports'],
    'data': ['security/ir.model.access.csv', 'data/ff_events_data.xml', 'views/ff_event_views.xml', 'views/ff_price_category_views.xml'],
    'post_init_hook': 'post_init',
    'installable': True,
    'license': 'LGPL-3',
}
