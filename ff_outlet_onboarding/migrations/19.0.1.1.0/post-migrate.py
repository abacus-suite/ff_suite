"""Contacts already onboarded as distributors are marked as distributors, so outlets can be linked to them."""
from odoo import SUPERUSER_ID, api


def migrate(cr, version):
    env = api.Environment(cr, SUPERUSER_ID, {})
    partners = env["res.partner"].with_context(active_test=False).search(
        [("ff_category_type", "=", "distributor"), ("ff_is_distributor", "=", False)])
    partners.write({"ff_is_distributor": True})
