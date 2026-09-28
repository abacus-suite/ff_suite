"""The figures behind the distributor outlet order summary.

The order itself holds one line per product - that is what the distributor
supplies - but the person reading it needs to know which outlet asked for what,
because that is how they will pick and deliver. Both views come off the same
demands, so they are worked out here rather than in the template.
"""
from odoo import models


class SaleOrder(models.Model):
    _inherit = 'sale.order'

    def ff_summary_outlets(self):
        """One block per outlet: its address and what it asked for.

        Outlets come in the order their demands were raised, which is the order
        the field visited them in, and a product asked for twice by the same
        outlet is added up rather than printed twice.
        """
        self.ensure_one()
        blocks = []
        by_outlet = {}
        for demand in self.ff_demand_ids.sorted(lambda d: (d.date, d.id)):
            outlet = demand.partner_id
            block = by_outlet.get(outlet)
            if block is None:
                block = {'outlet': outlet, 'address': self._ff_one_line_address(outlet), 'rows': {}}
                by_outlet[outlet] = block
                blocks.append(block)
            for line in demand.line_ids:
                row = block['rows'].setdefault(line.product_id, {
                    'product': line.product_id,
                    'code': self._ff_product_code(line.product_id),
                    'quantity': 0.0,
                    'uom': line.product_id.uom_id.name,
                })
                row['quantity'] += line.quantity
        for block in blocks:
            block['lines'] = list(block['rows'].values())
            block['total_qty'] = sum(row['quantity'] for row in block['lines'])
        return blocks

    def ff_summary_products(self):
        """Every product on the order with its total: what actually ships."""
        self.ensure_one()
        rows = {}
        for line in self.order_line.filtered('product_id'):
            row = rows.setdefault(line.product_id, {
                'product': line.product_id,
                'code': self._ff_product_code(line.product_id),
                'quantity': 0.0,
                'uom': line.product_uom_id.name if 'product_uom_id' in line._fields else line.product_id.uom_id.name,
            })
            row['quantity'] += line.product_uom_qty
        return list(rows.values())

    def _ff_product_code(self, product):
        template = product.product_tmpl_id
        return product.default_code or getattr(template, 'ff_sku_code', False) or ''

    def _ff_one_line_address(self, partner):
        parts = [partner.street, partner.street2, partner.city,
                 partner.state_id.name, partner.zip]
        return ', '.join(part for part in parts if part)
