"""The lists an outlet or distributor is described from.

MRP, scheme, chiller model and outlet category are the office's to maintain,
so each is a row in one master, told apart by its kind, and anything can be
added, renamed, reordered or switched off without touching the code.
"""
import re

from odoo import api, fields, models

KINDS = [
    ('mrp', 'MRP'),
    ('scheme', 'Scheme'),
    ('chiller_model', 'Chiller Model'),
    ('outlet_category', 'Outlet Category'),
]


class FfPartnerOption(models.Model):
    _name = 'ff.partner.option'
    _description = 'Outlet / Distributor Option'
    _order = 'kind, sequence, id'

    kind = fields.Selection(KINDS, required=True, index=True)
    name = fields.Char(required=True, translate=True)
    code = fields.Char(required=True, copy=False, help='Filled in from the name when left empty.')
    sequence = fields.Integer(default=10)
    amount = fields.Float(
        string='Scheme per Bottle (Rs.)', digits=(8, 2),
        help='Only for Schemes: the rupees taken off the MRP of every bottle before the outlet margin is applied.')
    needs_note = fields.Boolean(
        string='Needs a Description',
        help='Whoever picks this must also describe it, as with "Others".')
    active = fields.Boolean(default=True)
    line_ids = fields.One2many('ff.mrp.line', 'option_id', string='Products & Prices',
                               help='For an MRP: the products this MRP sells, each with its price.')

    @api.model_create_multi
    def create(self, vals_list):
        options = super().create(vals_list)
        for option in options.filtered(lambda o: o.kind == 'mrp' and not o.line_ids):
            option.ff_load_products()
        return options

    def ff_load_products(self):
        """Put every product the app sells on this MRP, at the price it has now (to be changed per product)."""
        Product = self.env['product.product'].sudo()
        for option in self:
            have = option.line_ids.product_id
            for product in Product.search([('sale_ok', '=', True)]) - have:
                tmpl = product.product_tmpl_id
                price = tmpl.ff_mrp if 'ff_mrp' in tmpl._fields and tmpl.ff_mrp else product.list_price
                self.env['ff.mrp.line'].create({'option_id': option.id, 'product_id': product.id, 'mrp': price})

    def ff_scheme_value(self):
        """The rupees off every bottle: the amount entered, else a number the name is made of ("20", "Rs 30 per bottle")."""
        self.ensure_one()
        if self.amount:
            return self.amount
        match = re.fullmatch(r'\s*(?:rs\.?|inr|₹)?\s*(\d+(?:\.\d+)?)\s*(?:rs\.?|inr|₹|/\s*bottle|per\s*bottle)?\s*',
                             self.name or '', re.IGNORECASE)
        return float(match.group(1)) if match else 0.0

    _kind_code_uniq = models.Constraint('UNIQUE(kind, code)', 'This option already exists for the list.')

    @api.model_create_multi
    def create(self, vals_list):
        for vals in vals_list:
            if not vals.get('code') and vals.get('name'):
                vals['code'] = re.sub(r'[^a-z0-9]+', '_', vals['name'].lower()).strip('_') or 'option'
        return super().create(vals_list)

    @api.model
    def ff_by_code(self, kind, code):
        """The option of this kind with that code, or an empty one."""
        return self.sudo().search([('kind', '=', kind), ('code', '=', code or '')], limit=1)

    @api.model
    def ff_choices(self, kind):
        return [{'code': o.code, 'name': o.name, 'needs_note': o.needs_note,
                 # A scheme is shown as its amount with the company's currency symbol.
                 'value': o.ff_scheme_value() if o.kind == 'scheme' else None}
                for o in self.sudo().search([('kind', '=', kind)])]


class FfMrpLine(models.Model):
    """One product of an MRP master, with its price."""
    _name = 'ff.mrp.line'
    _description = 'MRP Product Price'
    _order = 'option_id, product_id'

    option_id = fields.Many2one('ff.partner.option', required=True, ondelete='cascade', index=True)
    product_id = fields.Many2one('product.product', string='Product', required=True, ondelete='cascade',
                                 domain=[('sale_ok', '=', True)])
    code = fields.Char(related='product_id.default_code', string='Product Code', readonly=True)
    product_name = fields.Char(related='product_id.name', string='Product Name', readonly=True)
    mrp = fields.Float(string='MRP', digits=(10, 2))

    _option_product_uniq = models.Constraint('UNIQUE(option_id, product_id)', 'This product is already on the MRP.')


class ProductProduct(models.Model):
    _inherit = 'product.product'

    def _ff_partner_mrp(self, partner=None):
        """The MRP of this product for this partner: from the partner's onboarded MRP master (ff_mrp_id)
        if available in its product prices, otherwise the product template's default ff_mrp."""
        self.ensure_one()
        if partner:
            p = partner.sudo().commercial_partner_id
            mrp_opt = p.ff_mrp_id if 'ff_mrp_id' in p._fields else None
            if mrp_opt and 'line_ids' in mrp_opt._fields and mrp_opt.line_ids:
                line = mrp_opt.line_ids.filtered(lambda l: l.product_id.id == self.id)
                if line and line[0].mrp:
                    return line[0].mrp
        return self.product_tmpl_id.ff_mrp or self.lst_price or 0.0

    def ff_field_price(self, partner=None):
        price = super().ff_field_price(partner)
        if partner and not getattr(self.product_tmpl_id, 'ff_ptr', None):
            partner_mrp = self._ff_partner_mrp(partner)
            if partner_mrp:
                return partner_mrp
        return price
