from odoo import api, models


class AccountMove(models.Model):
    _name = 'account.move'
    _inherit = ['account.move', 'ff.attribution.mixin']

    @api.onchange('partner_id')
    def _onchange_partner_ff_attribution(self):
        if self.is_invoice(include_receipts=True):
            self._ff_attribution_from_partner()

    @api.model_create_multi
    def create(self, vals_list):
        moves = super().create(vals_list)
        moves.filtered(lambda m: m.is_invoice(include_receipts=True))._ff_attribution_from_partner()
        return moves
