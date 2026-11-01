"""Free goods on a demand: priced at 100% discount, delivered on request.

A free line carries the real price and a 100% discount, so it is worth nothing
on the demand and the value given away can still be reported. It never goes on
the distributor's order: the distributor is already made good by the debit note
raised with the demand, so there is nothing to quote or confirm. Instead the
distributor is asked, by message, to deliver the free goods, and the demand is
closed when somebody marks them delivered.
"""
import re

from odoo import api, fields, models
from odoo.exceptions import UserError


class FfDemandLine(models.Model):
    _inherit = 'ff.demand.line'

    discount = fields.Float(string='Discount %', digits=(5, 2), default=0.0)

    @api.depends('quantity', 'price_unit', 'discount', 'tax_ids')
    def _compute_subtotal(self):
        for line in self:
            price = line.price_unit * (1.0 - (line.discount or 0.0) / 100.0)
            untaxed = line.quantity * price
            tax = 0.0
            if line.tax_ids and untaxed:
                result = line.tax_ids.compute_all(price, currency=line.currency_id, quantity=line.quantity,
                                                  product=line.product_id, partner=line.partner_id)
                untaxed = result['total_excluded']
                tax = result['total_included'] - result['total_excluded']
            line.subtotal = untaxed
            line.price_tax = tax
            line.price_total = untaxed + tax

    @api.model_create_multi
    def create(self, vals_list):
        Product = self.env['product.product'].sudo()
        for vals in vals_list:
            if vals.get('is_foc'):
                vals['discount'] = 100.0
                if not vals.get('price_unit') and vals.get('product_id'):
                    vals['price_unit'] = Product.browse(vals['product_id']).ff_field_price()
        return super().create(vals_list)

    def write(self, vals):
        if vals.get('is_foc'):
            vals = dict(vals, discount=100.0)
            for line in self.filtered(lambda l: not l.price_unit):
                super(FfDemandLine, line).write({'price_unit': line.product_id.ff_field_price()})
        elif 'discount' in vals:
            # A free line stays free.
            free = self.filtered('is_foc')
            if free:
                super(FfDemandLine, free).write(dict(vals, discount=100.0))
                self -= free
        return super(FfDemandLine, self).write(vals) if self else True


class FfDemand(models.Model):
    _inherit = 'ff.demand'

    foc_status = fields.Selection([
        ('pending', 'To Request'), ('requested', 'Requested'), ('delivered', 'Delivered'),
    ], string='Free Goods', index=True, copy=False, tracking=True,
        help='Where the free goods on this demand stand: nothing is quoted for them, the distributor '
             'is asked to deliver and the demand is closed once they are delivered.')
    foc_requested_at = fields.Datetime(string='Requested On', readonly=True, copy=False)
    foc_delivered_at = fields.Datetime(string='Delivered On', readonly=True, copy=False)
    foc_note = fields.Char(string='Delivery Note')

    @api.model_create_multi
    def create(self, vals_list):
        demands = super().create(vals_list)
        for demand in demands.filtered(lambda d: d.line_ids.filtered('is_foc') and not d.foc_status):
            demand.foc_status = 'pending'
        return demands

    def _ff_refresh_state(self):
        """Free goods ride on the distributor's order, so they follow it: asked for when it
        goes out, delivered when it is supplied."""
        super()._ff_refresh_state()
        for demand in self.filtered(lambda d: d.foc_status and d.state != 'cancelled'):
            if demand.state == 'supplied':
                demand.foc_status = 'delivered'
            elif demand.order_ids or demand.request_id:
                demand.foc_status = 'requested'

    # ------------------------------------------------------------------
    # Asking the distributor to deliver, and closing it
    # ------------------------------------------------------------------
    def ff_foc_lines(self):
        self.ensure_one()
        return self.line_ids.filtered('is_foc')

    def ff_foc_message(self):
        """The delivery request, as the text the distributor receives."""
        self.ensure_one()
        outlet = self.partner_id
        address = ', '.join(filter(None, [outlet.street, outlet.street2, outlet.city])) or ''
        lines = ['Free goods - please deliver', 'Outlet: %s' % outlet.display_name]
        if address:
            lines.append('Address: %s' % address)
        phone = outlet.phone or getattr(outlet, 'mobile', '') or ''
        if phone:
            lines.append('Phone: %s' % phone)
        lines.append('')
        lines += ['- %s x %s' % (line.product_id.display_name, ('%g' % line.quantity)) for line in self.ff_foc_lines()]
        lines += ['', 'Reference: %s' % self.name, 'Raised by: %s' % self.employee_id.name,
                  'These goods are free of charge and are covered by our debit note.']
        return '\n'.join(lines)

    def ff_foc_request(self, employee, distributor=None):
        """Mark the free goods as asked for and give back the message to send."""
        self.ensure_one()
        if not self.ff_foc_lines():
            raise UserError(self.env._('%s has no free goods.', self.name))
        if self.foc_status == 'delivered':
            raise UserError(self.env._('The free goods on %s were already delivered.', self.name))
        distributor = distributor or self.distributor_id
        if not distributor or not distributor.sudo().ff_is_distributor:
            raise UserError(self.env._('Choose the distributor who delivers the free goods.'))
        values = {'foc_status': 'requested', 'foc_requested_at': fields.Datetime.now()}
        if self.distributor_id != distributor:
            values['distributor_id'] = distributor.id
        self.sudo().write(values)
        self.sudo()._ff_refresh_state()
        number = re.sub(r'\D', '', distributor.phone or getattr(distributor, 'mobile', '') or '')
        return {'message': self.ff_foc_message(), 'phone': number or None, 'distributor': distributor}

    def ff_foc_deliver(self, note=None):
        for demand in self:
            if not demand.ff_foc_lines():
                raise UserError(self.env._('%s has no free goods.', demand.name))
            demand.sudo().write({'foc_status': 'delivered', 'foc_delivered_at': fields.Datetime.now(),
                                 'foc_note': note or demand.foc_note})
            demand.sudo()._ff_refresh_state()
        return True

    def action_foc_deliver(self):
        return self.ff_foc_deliver()
