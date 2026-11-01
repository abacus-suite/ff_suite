{
    'name': 'Field Force - Multi Company',
    'version': '19.0.1.0.0',
    'category': 'Human Resources/Field Force',
    'summary': 'Every Field Force record belongs to a company, and people see only their working company',
    'description': """
The employee's company is their working company. Everything they record -
visits, tasks, demands, collections, samples, plans - carries that company, and
a record rule limits each user to the companies they are working in.
""",
    'author': 'Field Force Suite',
    'depends': ['ff_allowance', 'ff_approvals', 'ff_attendance', 'ff_base', 'ff_beat', 'ff_clients', 'ff_collections', 'ff_demand', 'ff_expenses', 'ff_foc', 'ff_forms', 'ff_live_map', 'ff_outlet_ledger', 'ff_returns', 'ff_targets', 'ff_tasks', 'ff_visit_steps', 'ff_visit_tasks', 'ff_visits'],
    'data': ['security/ff_multicompany_security.xml'],
    'installable': True,
    'license': 'LGPL-3',
}
