"""The outlet is billed for what was delivered, and nothing more."""
from odoo import fields, models


class FfDemandDelivery(models.Model):
    _inherit = 'ff.demand.delivery'

    outlet_invoice_ids = fields.One2many('ff.outlet.invoice', 'delivery_id', string='Outlet Invoices')

    def _ff_invoice(self):
        super()._ff_invoice()
        Invoice = self.env['ff.outlet.invoice'].sudo()
        today = fields.Date.context_today(self)
        for delivery in self:
            amount = round(delivery.amount, 2)
            if amount <= 0 or delivery.outlet_invoice_ids:
                continue
            demand = delivery.demand_id
            Invoice.create({
                'name': self.env['ir.sequence'].sudo().next_by_code('ff.outlet.invoice') or '/',
                'distributor_id': demand.distributor_id.id or demand.request_id.partner_id.id,
                'partner_id': demand.partner_id.id,
                'employee_id': demand.employee_id.id,
                'date': today,
                'due_date': Invoice._ff_due_date(demand.partner_id, today),
                'amount_total': amount,
                'company_id': demand.company_id.id,
                'demand_id': demand.id,
                'delivery_id': delivery.id,
                'note': self.env._('Delivered under %(demand)s (%(delivery)s).', demand=demand.name,
                                   delivery=delivery.name),
            })
