"""Visit outcomes became a master: link existing visits to the matching record."""
from odoo import SUPERUSER_ID, api


def migrate(cr, version):
    env = api.Environment(cr, SUPERUSER_ID, {})
    Visit = env['ff.visit'].with_context(active_test=False)
    for outcome in env['ff.visit.outcome'].with_context(active_test=False).search([('code', '!=', False)]):
        Visit.search([('outcome', '=', outcome.code), ('outcome_id', '=', False)]).write({'outcome_id': outcome.id})
