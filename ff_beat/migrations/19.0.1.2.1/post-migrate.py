"""Assign route employees to the contacts of their routes."""
from odoo import SUPERUSER_ID, api


def migrate(cr, version):
    env = api.Environment(cr, SUPERUSER_ID, {})
    env['ff.beat'].with_context(active_test=False).search([]).action_sync_contact_employees()
