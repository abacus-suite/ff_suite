from odoo import models


def price_basis(env):
    return env['ir.config_parameter'].sudo().get_param('ff_base.price_basis') or 'product'


class ProductProduct(models.Model):
    _inherit = 'product.product'

    def _ff_margin_price(self, margin):
        """MRP less ``margin`` %, or None when the product has no MRP or there is no margin to apply."""
        self.ensure_one()
        mrp = self.product_tmpl_id.ff_mrp
        if not mrp or not margin:
            return None
        return round(mrp * (1.0 - margin / 100.0), 2)

    def _ff_scheme_amount(self, outlet):
        """The rupees off every bottle that this outlet's scheme gives (0 when it has none)."""
        option = outlet.ff_scheme_id if 'ff_scheme_id' in outlet._fields else False
        return option.ff_scheme_value() if option and hasattr(option, 'ff_scheme_value') else 0.0

    def _ff_total_margin(self, distributor=None):
        """The total margin shared between a distributor and its outlets: the distributor's own deal, else the company's."""
        own = getattr(distributor, 'total_margin_pct', 0.0) if distributor else 0.0
        return own or self.env.company.sudo().ff_total_margin

    def _ff_pass_through_margin(self, distributor):
        """The margin a distributor normally gives the outlets it supplies: the total less its own share
        (Total 30, distributor 10 -> outlets 20), else the margin set on the distributor."""
        if not distributor:
            return 0.0
        total = self._ff_total_margin(distributor)
        own = getattr(distributor, 'distributor_margin_pct', 0.0)
        if own and total:
            return max(total - own, 0.0)
        return distributor.ff_margin or 0.0

    def ff_field_price(self, partner=None):
        """To an outlet: (MRP less the outlet's scheme per bottle) less the margin the outlet agreed.

        MRP 149, scheme 30, margin 20% -> (149 - 30) less 20% = 95.20. The outlet is invoiced at the margin
        it was promised, even when that is more than the distributor normally gives: the difference is made
        good to the distributor with a debit note on every delivery. An outlet with no margin of its own is
        priced at the margin its distributor passes on.
        """
        price = super().ff_field_price(partner)
        if partner and price_basis(self.env) == 'margin':
            outlet = partner.sudo().commercial_partner_id
            distributor = self.env.context.get('ff_distributor') or outlet.ff_distributor_id
            if distributor and not isinstance(distributor, models.BaseModel):
                distributor = self.env['res.partner'].sudo().browse(distributor)
            distributor = distributor.sudo().commercial_partner_id if distributor else None
            margin = outlet.ff_margin or self._ff_pass_through_margin(distributor)
            mrp = self.product_tmpl_id.ff_mrp
            scheme = self._ff_scheme_amount(outlet)
            if mrp and (margin or scheme):
                return round(max(mrp - scheme, 0.0) * (1.0 - (margin or 0.0) / 100.0), 2)
        return price

    def ff_distributor_price(self, partner=None):
        """To a distributor: MRP less the total margin %, whatever the distributor's own margin.

        Only when pricing by margin; otherwise the product's PTS.
        """
        price = super().ff_distributor_price(partner)
        if price_basis(self.env) == 'margin':
            company = partner.company_id if partner and partner.company_id else self.env.company
            total = (getattr(partner.sudo(), 'total_margin_pct', 0.0) if partner else 0.0) or company.sudo().ff_total_margin
            margin_price = self._ff_margin_price(total)
            if margin_price is not None:
                return margin_price
        return price

    def ff_order_price(self, billed_to, outlet=None):
        if price_basis(self.env) != 'margin' or not billed_to:
            return super().ff_order_price(billed_to, outlet)
        if billed_to.sudo().ff_is_distributor:
            return self.ff_distributor_price(billed_to)
        return self.ff_field_price(billed_to)
