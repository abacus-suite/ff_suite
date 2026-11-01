from odoo import api, fields, models


class FfExpenseClaim(models.Model):
    """The claim already carries the employee, team and department. What it misses
    is where the money was spent, so travel costs can be compared with the sales
    of the same route."""
    _inherit = 'ff.expense.claim'

    ff_route_id = fields.Many2one('ff.beat', string='Route', index=True)
    ff_district_id = fields.Many2one('ff.district', string='City / District', index=True)

    @api.onchange('partner_id')
    def _onchange_partner_ff_attribution(self):
        for claim in self:
            contact = claim.partner_id
            if contact and not claim.ff_route_id:
                claim.ff_route_id = contact.ff_route_ids[:1].id
            if contact and not claim.ff_district_id:
                claim.ff_district_id = contact.ff_district_id.id
