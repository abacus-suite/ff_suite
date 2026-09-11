"""Journey plans: attach existing daily plans to monthly plans with customer lines,
and give existing field contacts their employees (from routes and creator)."""
from odoo import SUPERUSER_ID, api


def migrate(cr, version):
    env = api.Environment(cr, SUPERUSER_ID, {})
    RoutePlan = env['ff.route.plan']
    Day = env['ff.beat.plan'].with_context(active_test=False)
    for day in Day.search([]):
        vals = {}
        if not day.plan_id:
            vals['plan_id'] = RoutePlan._ff_get(day.employee_id, day.date).id
        if not day.customer_line_ids:
            vals['customer_line_ids'] = Day._ff_customer_line_cmds(day.beat_id)
        if vals:
            day.write(vals)
    Day.search([])._ff_link_visits()

    Partner = env['res.partner'].with_context(active_test=False)
    for partner in Partner.search([('ff_is_client', '=', True), ('ff_employee_ids', '=', False)]):
        employees = partner.ff_beat_line_ids.beat_id.employee_ids | partner.ff_created_by_employee_id
        if employees:
            partner.ff_employee_ids = [(6, 0, employees.ids)]
