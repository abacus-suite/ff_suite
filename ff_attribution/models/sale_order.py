from odoo import api, models


class SaleOrder(models.Model):
    """``ff_employee_id`` already exists for app orders; this adds the rest of the
    stamp and fills it in for orders typed in the back office too."""
    _name = 'sale.order'
    _inherit = ['sale.order', 'ff.attribution.mixin']

    @api.onchange('partner_id')
    def _onchange_partner_ff_attribution(self):
        self._ff_attribution_from_partner()

    @api.model_create_multi
    def create(self, vals_list):
        orders = super().create(vals_list)
        orders._ff_attribution_from_partner()
        return orders

    def _prepare_invoice(self):
        vals = super()._prepare_invoice()
        if 'ff_employee_id' in self.env['account.move']._fields:
            vals.update(self._ff_attribution_values())
        return vals
