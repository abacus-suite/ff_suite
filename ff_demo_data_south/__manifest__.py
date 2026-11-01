{
    'name': 'Field Force - Demo Data (South India)',
    'version': '19.0.1.0.0',
    'category': 'Human Resources/Field Force',
    'summary': '30 employees in 4 levels across Tamil Nadu, Kerala and Bangalore, 60 customers and every area filled',
    'description': """
Install on a TEST database only, after (or without) "Field Force - Demo Data".

People - Odoo login and app login, password FieldForce@123:
  sin.head          Level 1  National Sales Head        (all)
  sin.tn / sin.kl / sin.ka   Level 2  State managers    (hierarchy)
  sin.chn, sin.cbe, sin.koc, sin.tvm, sin.bln, sin.bls   Level 3  Area managers (hierarchy)
  sin.rep01 ... sin.rep20    Level 4  Sales executives  (own) - app login only

Filled for every person: code, designation, team, shift, allowance policy,
routes, devices, app login, contact details, private address, birthday,
emergency contact and more. History for the last 7 days covers attendance,
live location pings, visits, visit steps, stock counts, forms, demands,
collections and deposits, returns, expenses, travel allowance claims,
regularisations, leaves, tasks, targets, alerts and notifications.
""",
    'author': 'Field Force Suite',
    'depends': [
        'ff_dashboard', 'ff_demand', 'ff_collections', 'ff_expenses', 'ff_targets', 'ff_tasks', 'ff_foc',
        'ff_returns', 'ff_forms', 'ff_visit_steps', 'ff_allowance', 'ff_alerts', 'ff_leaves', 'ff_approvals',
    ],
    'data': [],
    'post_init_hook': 'post_init_hook',
    'installable': True,
    'license': 'LGPL-3',
}
