"""A distributor's stock, as the company can follow it.

Stock comes in when the company ships to the distributor (or the distributor
records a receipt) and goes out when the distributor delivers to an outlet
against a demand, or returns or writes something off. Every movement is a row
here, so the stock on hand is just their sum and the in/out report is a list.
"""
from odoo import api, fields, models

KINDS = [
    ('opening', 'Opening Stock'),
    ('receipt', 'Stock Received'),
    ('adjust_in', 'Adjustment (+)'),
    ('delivery', 'Delivered to Outlet'),
    ('return', 'Returned / Damaged'),
    ('adjust_out', 'Adjustment (-)'),
]
IN_KINDS = ('opening', 'receipt', 'adjust_in')


class DealerStockMove(models.Model):
    _name = 'l4e.dealer.stock.move'
    _description = 'Distributor Stock Movement'
    _order = 'date desc, id desc'

    distributor_id = fields.Many2one('res.partner', string='Distributor', required=True, index=True,
                                     domain=[('ff_is_distributor', '=', True)], ondelete='cascade')
    product_id = fields.Many2one('product.product', required=True, index=True, ondelete='cascade')
    date = fields.Datetime(required=True, default=fields.Datetime.now, index=True)
    kind = fields.Selection(KINDS, required=True, index=True)
    direction = fields.Selection([('in', 'In'), ('out', 'Out')], compute='_compute_direction', store=True, index=True)
    uom_id = fields.Many2one(related='product_id.uom_id', string='Unit')
    quantity = fields.Float(required=True, digits='Product Unit', help='Always a positive number; the kind says which way.')
    signed_qty = fields.Float(compute='_compute_direction', store=True, digits='Product Unit')
    reference = fields.Char(help='A delivery, a transfer or a receipt number.')
    partner_id = fields.Many2one('res.partner', string='Outlet', help='The outlet it was delivered to.')
    delivery_line_id = fields.Many2one('ff.demand.delivery.line', ondelete='set null', copy=False)
    note = fields.Char()
    entered_by = fields.Char()
    company_id = fields.Many2one('res.company', required=True, default=lambda self: self.env.company)

    @api.depends('kind', 'quantity')
    def _compute_direction(self):
        for move in self:
            incoming = move.kind in IN_KINDS
            move.direction = 'in' if incoming else 'out'
            move.signed_qty = move.quantity if incoming else -move.quantity

    @api.model
    def ff_on_hand(self, distributor, upto=None):
        """{product id: units} for this distributor, optionally as at a moment."""
        domain = [('distributor_id', '=', distributor.id)]
        if upto:
            domain.append(('date', '<', upto))
        groups = self.sudo()._read_group(domain, ['product_id'], ['signed_qty:sum'])
        return {product.id: total for product, total in groups}


class FfDemandDelivery(models.Model):
    _inherit = 'ff.demand.delivery'

    @api.model_create_multi
    def create(self, vals_list):
        deliveries = super().create(vals_list)
        Move = self.env['l4e.dealer.stock.move'].sudo()
        for delivery in deliveries:
            distributor = delivery.demand_id.distributor_id or delivery.demand_id.request_id.partner_id
            if not distributor:
                continue
            for line in delivery.line_ids:
                Move.create({
                    'distributor_id': distributor.id, 'product_id': line.product_id.id,
                    'date': delivery.date, 'kind': 'delivery', 'quantity': line.quantity,
                    'reference': delivery.name, 'partner_id': delivery.partner_id.id,
                    'delivery_line_id': line.id, 'entered_by': delivery.entered_by,
                    'company_id': delivery.company_id.id,
                })
        return deliveries
