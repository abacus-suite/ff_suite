{
    'name': 'Field Force - Remove Demo Data',
    'version': '19.0.1.0.0',
    'category': 'Human Resources/Field Force',
    'summary': 'Delete the employees, customers and history the demo modules created',
    'description': """
The demo modules build their data in Python, so uninstalling them takes nothing
away. Installing this module removes what they made, and leaves everything else
alone.

What goes:
  * the demo logins (demo.* and sin.*) and their employees
  * every visit, demand, collection, deposit, expense, claim, task, target,
    attendance record and location ping belonging to those people
  * the customers the demo staff added, and the ones marked "(Demo)"
  * the teams, routes, districts, products and templates marked "(Demo)"

What stays: everything else. A record is removed only when it points at a demo
login, a demo employee, a demo customer, or carries the marker in its own name.

Run it again whenever you like from Field Force > Configuration > Remove Demo
Data. It always finds less than the time before.
""",
    'author': 'Field Force Suite',
    'depends': ['ff_base'],
    'data': [
        'security/ir.model.access.csv',
        'views/ff_demo_purge_views.xml',
    ],
    'post_init_hook': 'post_init_hook',
    'installable': True,
    'license': 'LGPL-3',
}
