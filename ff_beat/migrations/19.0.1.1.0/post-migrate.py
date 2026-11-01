"""Route type became mandatory: existing routes become "Beat" routes."""
from odoo import SUPERUSER_ID, api


def migrate(cr, version):
    env = api.Environment(cr, SUPERUSER_ID, {})
    route_type = env.ref('ff_beat.route_type_beat', raise_if_not_found=False)
    if route_type:
        env['ff.beat'].with_context(active_test=False).search(
            [('route_type_id', '=', False)]).write({'route_type_id': route_type.id})
