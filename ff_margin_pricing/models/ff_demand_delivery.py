from odoo import api, models


class FfDemandDelivery(models.Model):
    _inherit = 'ff.demand.delivery'

    @api.model_create_multi
    def create(self, vals_list):
        deliveries = super().create(vals_list)
        for delivery in deliveries:
            delivery._ff_margin_note()
        return deliveries

    def _ff_margin_note(self):
        """The outlet was given a bigger margin than the distributor has: the distributor would sell below what
        it paid. The company owes it the difference on what was delivered, so a debit note is raised."""
        self.ensure_one()
        demand = self.demand_id
        if not demand.margin_excess or not demand.distributor_id:
            return
        lines = self.line_ids.filtered(lambda l: not getattr(l.demand_line_id, 'is_foc', False) and l.quantity)
        partner = demand.partner_id
        mrp_fn = lambda p: p._ff_partner_mrp(partner) if hasattr(p, '_ff_partner_mrp') else (p.product_tmpl_id.ff_mrp or 0.0)
        mrp_value = sum(l.quantity * mrp_fn(l.product_id) for l in lines)
        amount = round(mrp_value * demand.margin_excess / 100.0, 2)
        if amount <= 0:
            return
        reason = self.env._(
            'Outlet margin %(o)s%% is above the distributor margin %(d)s%%: the distributor sells below its cost.',
            d='%g' % demand.margin_distributor, o='%g' % demand.margin_outlet)
        self.env['ff.distributor.note'].sudo().create({
            'kind': 'debit', 'distributor_id': demand.distributor_id.id, 'partner_id': demand.partner_id.id,
            'employee_id': demand.employee_id.id, 'demand_id': demand.id, 'delivery_id': self.id,
            'reason': reason, 'source': 'margin', 'margin_excess': demand.margin_excess,
            'company_id': demand.company_id.id,
            'line_ids': [(0, 0, {
                'product_id': l.product_id.id, 'quantity': l.quantity,
                'price_unit': round(mrp_fn(l.product_id) * demand.margin_excess / 100.0, 2),
            }) for l in lines],
        })
