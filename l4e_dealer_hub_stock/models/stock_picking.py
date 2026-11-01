from odoo import models


class StockPicking(models.Model):
    _inherit = 'stock.picking'

    def _action_done(self):
        result = super()._action_done()
        Move = self.env['l4e.dealer.stock.move'].sudo()
        for picking in self.filtered(lambda p: p.state == 'done' and p.picking_type_code == 'outgoing'):
            distributor = picking.partner_id.commercial_partner_id
            if not distributor.ff_is_distributor:
                continue
            for move in picking.move_ids.filtered(lambda m: m.state == 'done' and m.quantity):
                if Move.search_count([('reference', '=', picking.name), ('product_id', '=', move.product_id.id),
                                      ('kind', '=', 'receipt')]):
                    continue
                Move.create({
                    'distributor_id': distributor.id, 'product_id': move.product_id.id, 'kind': 'receipt',
                    'quantity': move.quantity, 'reference': picking.name, 'entered_by': 'Company shipment',
                    'company_id': picking.company_id.id,
                })
            if 'ff.notification' in self.env:
                order = picking.sale_id
                employees = (order.ff_employee_id | distributor.ff_employee_ids | picking.user_id.employee_id) if order else (distributor.ff_employee_ids | picking.user_id.employee_id)
                for emp in employees:
                    self.env['ff.notification'].sudo().ff_push(
                        title=self.env._('Distributor Order Delivered'),
                        body=self.env._('Delivery %(name)s for distributor %(dist)s has been completed.',
                                        name=picking.name, dist=distributor.name),
                        kind='info',
                        employee=emp,
                        record=order or picking,
                    )
        return result
