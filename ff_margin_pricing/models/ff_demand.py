from odoo import api, fields, models

from .product import price_basis


class FfDemand(models.Model):
    _inherit = 'ff.demand'

    margin_outlet = fields.Float(string='Outlet Margin %', digits=(5, 2), readonly=True, copy=False)
    margin_distributor = fields.Float(string='Distributor Margin %', digits=(5, 2), readonly=True, copy=False)
    margin_total = fields.Float(string='Company Default Margin %', digits=(5, 2), readonly=True, copy=False)
    margin_excess = fields.Float(
        string='Distributor Shortfall %', digits=(5, 2), readonly=True, copy=False,
        help='How far the outlet margin is above the distributor margin. The distributor would sell below '
             'what it paid, so the company makes it good with a debit note on every delivery.')
    distributor_profit = fields.Monetary(string='Distributor Profit', compute='_compute_margin_money')
    outlet_profit = fields.Monetary(string='Outlet Profit', compute='_compute_margin_money')

    @api.depends('line_ids.quantity', 'line_ids.is_foc', 'margin_outlet', 'margin_distributor', 'margin_total')
    def _compute_margin_money(self):
        """MRP 100, company 30%, distributor 20%, outlet 10%: the distributor buys at 70 and sells at 80
        (profit 10 a unit); the outlet buys at 80 and sells at 90 (profit 10 a unit)."""
        for demand in self:
            mrp_value = sum(l.quantity * (l.product_id.product_tmpl_id.ff_mrp or 0.0)
                            for l in demand.line_ids if not getattr(l, 'is_foc', False))
            demand.distributor_profit = round(mrp_value * (demand.margin_total - demand.margin_distributor) / 100.0, 2)
            demand.outlet_profit = round(mrp_value * (demand.margin_distributor - demand.margin_outlet) / 100.0, 2)

    @api.model
    def ff_create_from_app(self, employee, partner, data):
        """The outlet's rate from the margin formula includes the GST. The unit price of the demand is that rate
        without the GST (97.30 at 5% is 92.67), and the tax is then added on the lines as usual, so the demand
        totals what the PO Summary showed."""
        uuid = data.get('uuid') or False
        resent = bool(uuid and self.sudo().search_count([('client_uuid', '=', uuid)]))
        demand = super().ff_create_from_app(employee, partner, data)
        if not resent and price_basis(self.env) == 'margin' and not demand.partner_id.sudo().ff_is_distributor:
            for line in demand.sudo().line_ids.filtered(
                    lambda l: l.price_unit > 0 and not getattr(l, 'is_foc', False)):
                rate = sum(t.amount for t in line.tax_ids if t.amount_type == 'percent')
                if rate:
                    line.price_unit = round(line.price_unit / (1.0 + rate / 100.0), 2)
        return demand

    @api.model_create_multi
    def create(self, vals_list):
        demands = super().create(vals_list)
        if price_basis(self.env) == 'margin':
            for demand in demands:
                demand._ff_fix_margins()
        return demands

    def _ff_fix_margins(self):
        """Write down the margins as they stand when the demand is raised, so a later change
        to a contact's margin never alters what was promised for this demand.

        Total 30, the distributor keeps 10, outlets are normally given 20. An outlet that was promised 30 is
        invoiced at 30, so the distributor is 10 short: that 10 is the excess the company makes good.
        """
        self.ensure_one()
        Product = self.env['product.product']
        outlet = self.partner_id.sudo().commercial_partner_id.ff_margin
        distributor_partner = self.distributor_id.sudo().commercial_partner_id if self.distributor_id else None
        total = Product._ff_total_margin(distributor_partner) or self.company_id.sudo().ff_total_margin
        # What the distributor passes on to outlets; the company margin when it has none.
        distributor = Product._ff_pass_through_margin(distributor_partner) or total
        self.write({
            'margin_outlet': outlet, 'margin_distributor': distributor, 'margin_total': total,
            'margin_excess': max(outlet - distributor, 0.0),
        })

    def _ff_refix_distributor(self):
        """A demand sent to another distributor is settled against that distributor's margin."""
        for demand in self.filtered(lambda d: d.margin_total or price_basis(self.env) == 'margin'):
            demand._ff_fix_margins()

    def _ff_make_request(self, distributor, employee=None):
        request = super()._ff_make_request(distributor, employee)
        self._ff_refix_distributor()
        return request
