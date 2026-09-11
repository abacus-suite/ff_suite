"""Contact category became mandatory: give existing field contacts the default one."""
from odoo import SUPERUSER_ID, api


def migrate(cr, version):
    env = api.Environment(cr, SUPERUSER_ID, {})
    category = env.ref('ff_clients.contact_category_customer', raise_if_not_found=False)
    if not category:
        return
    env['res.partner'].with_context(active_test=False).search([
        ('ff_is_client', '=', True), ('ff_category_id', '=', False),
    ]).write({'ff_category_id': category.id})
