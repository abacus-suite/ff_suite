{
    'name': 'Field Force - Demo Data',
    'version': '19.0.1.0.0',
    'category': 'Human Resources/Field Force',
    'summary': 'A 3-level team of 6, 15 beats, 30 customers and 10 days of attendance, visits, demands and collections',
    'description': """
Install on a test database to try every role.

People (Odoo login / app login - password Aixolo@123 for both):
  demo.head      Ravi Menon      Sales Head      (all employees)
  demo.north     Anil Kumar      Team North lead (hierarchy)
  demo.south     Divya Nair      Team South lead (hierarchy)
  demo.rep1      Arjun Das       Team North rep
  demo.rep2      Fathima Rahman  Team North rep
  demo.rep3      Suresh Babu     Team South rep

Never install on a live database: it creates users, customers and history.
""",
    'author': 'Field Force Suite',
    'depends': [
        'ff_dashboard', 'ff_demand', 'ff_collections', 'ff_expenses', 'ff_targets', 'ff_tasks', 'ff_foc',
    ],
    'data': [],
    'post_init_hook': 'post_init_hook',
    'installable': True,
    'license': 'LGPL-3',
}
