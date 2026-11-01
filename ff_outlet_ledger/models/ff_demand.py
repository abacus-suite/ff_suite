from odoo import api, fields, models
from odoo.exceptions import UserError


class FfDemand(models.Model):
    _inherit = 'ff.demand'

    outlet_invoice_ids = fields.One2many('ff.outlet.invoice', 'demand_id', string='Outlet Invoices')
    outlet_invoice_count = fields.Integer(compute='_compute_outlet_invoice_count')

    @api.depends('outlet_invoice_ids')
    def _compute_outlet_invoice_count(self):
        for demand in self:
            demand.outlet_invoice_count = len(demand.outlet_invoice_ids)

    def action_open_outlet_invoices(self):
        self.ensure_one()
        return {
            'type': 'ir.actions.act_window', 'name': self.env._('Outlet Invoices'),
            'res_model': 'ff.outlet.invoice', 'view_mode': 'list,form',
            'domain': [('demand_id', '=', self.id)],
        }

    def action_ff_outlet_invoice(self):
        """Raise the outlet's invoice by hand, once a distributor has confirmed an order for it."""
        made = self.env['ff.outlet.invoice']
        for demand in self:
            orders = demand.order_ids.filtered(lambda o: o.state in ('sale', 'done'))
            if not orders:
                raise UserError(self.env._('%s has no confirmed distributor order yet.', demand.name))
            for order in orders:
                made |= self.env['ff.outlet.invoice'].ff_from_order(order)
        if not made:
            raise UserError(self.env._('Nothing to invoice: the outlet invoice already exists or the amount is nil.'))
        return True
