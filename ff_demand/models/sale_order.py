from odoo import api, fields, models


class SaleOrder(models.Model):
    """A quotation raised from demand knows which outlets it serves."""
    _inherit = 'sale.order'

    ff_demand_ids = fields.Many2many('ff.demand', 'ff_demand_order_rel', 'order_id', 'demand_id',
                                     string='Outlet Demands', copy=False)
    ff_demand_count = fields.Integer(compute='_compute_ff_demand_count')

    @api.depends('ff_demand_ids')
    def _compute_ff_demand_count(self):
        for order in self:
            order.ff_demand_count = len(order.ff_demand_ids)

    def action_open_demands(self):
        self.ensure_one()
        return {
            'type': 'ir.actions.act_window',
            'name': self.env._('Outlet Demands'),
            'res_model': 'ff.demand',
            'domain': [('id', 'in', self.ff_demand_ids.ids)],
            'view_mode': 'list,form',
        }

    def _ff_distributor_sent(self):
        """Called once an order has been sent to a distributor from the app.

        Empty here on purpose. Whatever tells the distributor - a portal link,
        an email - lives in the module that owns that, and hooks in by
        overriding this, so the demand module never has to know it exists.
        """
        return True

    def action_confirm(self):
        result = super().action_confirm()
        self.mapped('ff_demand_ids')._ff_refresh_state()
        return result
