"""FOC schemes: how many free units a quantity earns.

A scheme names what must be bought (products, or whole categories), the slabs
("10 or more: 1 free, 25 or more: 3 free") and what is given free - the same
product, or another one. Quantities count per product, or all the scheme's
products together. "Repeat" turns the first slab into "every 10 gives 1".
"""
from odoo import api, fields, models
from odoo.exceptions import ValidationError


class FfFocScheme(models.Model):
    _name = 'ff.foc.scheme'
    _description = 'FOC Scheme'
    _order = 'sequence, id desc'

    name = fields.Char(required=True)
    sequence = fields.Integer(default=10)
    active = fields.Boolean(default=True)
    company_id = fields.Many2one('res.company', default=lambda self: self.env.company)
    date_from = fields.Date(string='Valid From')
    date_to = fields.Date(string='Valid To')
    product_ids = fields.Many2many('product.product', 'ff_foc_scheme_product_rel', string='Buy Products',
                                   help='Leave empty to use the categories below.')
    categ_ids = fields.Many2many('product.category', string='Buy Categories')
    basis = fields.Selection([
        ('product', 'Per product (each product counted on its own)'),
        ('combined', 'Combined (all scheme products added together)'),
    ], required=True, default='product')
    slab_ids = fields.One2many('ff.foc.slab', 'scheme_id', string='Slabs', copy=True)
    repeat = fields.Boolean(string='Repeat Every Slab',
                            help='With one slab of 10 → 1: 20 bought gives 2 free, 30 gives 3.')
    free_product_id = fields.Many2one('product.product', string='Free Product',
                                      help='Leave empty to give the same product free.')
    department_ids = fields.Many2many('hr.department', string='Departments', help='Empty = every department.')
    customer_category_ids = fields.Many2many('ff.contact.category', string='Customer Categories',
                                             help='Empty = every customer.')
    note = fields.Char(help='How the rep explains it to the outlet.')
    summary = fields.Char(compute='_compute_summary')

    @api.depends('slab_ids.min_qty', 'slab_ids.free_qty', 'repeat', 'free_product_id', 'basis')
    def _compute_summary(self):
        for scheme in self:
            parts = []
            for slab in scheme.slab_ids.sorted('min_qty'):
                parts.append('%s%s + %s free' % ('every ' if scheme.repeat else '', _num(slab.min_qty), _num(slab.free_qty)))
            text = ', '.join(parts) or 'No slabs'
            if scheme.free_product_id:
                text += ' (%s)' % scheme.free_product_id.display_name
            scheme.summary = text

    @api.constrains('slab_ids', 'date_from', 'date_to')
    def _check(self):
        for scheme in self:
            if scheme.date_from and scheme.date_to and scheme.date_to < scheme.date_from:
                raise ValidationError(self.env._('The scheme ends before it starts.'))
            for slab in scheme.slab_ids:
                if slab.min_qty <= 0 or slab.free_qty <= 0:
                    raise ValidationError(self.env._('Slab quantities must be more than zero.'))

    # ------------------------------------------------------------------
    @api.model
    def ff_applicable(self, employee=None, partner=None, day=None):
        day = day or (employee._ff_today() if employee else fields.Date.context_today(self))
        schemes = self.sudo().search([
            ('company_id', 'in', (False, (employee.company_id if employee else self.env.company).id)),
            '|', ('date_from', '=', False), ('date_from', '<=', day),
            '|', ('date_to', '=', False), ('date_to', '>=', day),
        ])
        if employee:
            schemes = schemes.filtered(lambda s: not s.department_ids or employee.department_id in s.department_ids)
        if partner:
            category = partner.commercial_partner_id.ff_category_id or partner.ff_category_id
            schemes = schemes.filtered(lambda s: not s.customer_category_ids or category in s.customer_category_ids)
        return schemes.filtered('slab_ids')

    def _ff_covers(self, product):
        self.ensure_one()
        if self.product_ids:
            return product in self.product_ids
        if self.categ_ids:
            return product.categ_id in self.env['product.category'].sudo().search([('id', 'child_of', self.categ_ids.ids)])
        return False

    def _ff_free_for(self, quantity):
        """Free units earned by ``quantity``."""
        self.ensure_one()
        slabs = self.slab_ids.sorted('min_qty')
        if self.repeat and slabs:
            first = slabs[0]
            return int(quantity // first.min_qty) * first.free_qty if quantity >= first.min_qty else 0.0
        reached = slabs.filtered(lambda slab: quantity >= slab.min_qty)
        return reached[-1].free_qty if reached else 0.0

    @api.model
    def ff_compute(self, employee, partner, lines, day=None):
        """``lines``: [(product, quantity)] paid lines. Returns [{scheme, product, quantity, bought}]."""
        free = []
        for scheme in self.ff_applicable(employee, partner, day):
            covered = [(product, qty) for product, qty in lines if qty > 0 and scheme._ff_covers(product)]
            if not covered:
                continue
            if scheme.basis == 'combined':
                total = sum(qty for _product, qty in covered)
                units = scheme._ff_free_for(total)
                if units:
                    product = scheme.free_product_id or max(covered, key=lambda row: row[1])[0]
                    free.append({'scheme': scheme, 'product': product, 'quantity': units, 'bought': total})
            else:
                for product, qty in covered:
                    units = scheme._ff_free_for(qty)
                    if units:
                        free.append({'scheme': scheme, 'product': scheme.free_product_id or product,
                                     'quantity': units, 'bought': qty})
        return free

    def ff_payload(self):
        return [{
            'id': scheme.id,
            'name': scheme.name,
            'summary': scheme.summary,
            'note': scheme.note or None,
            'valid_to': scheme.date_to.isoformat() if scheme.date_to else None,
            'product_ids': scheme.product_ids.ids,
            'category_ids': scheme.categ_ids.ids,
            'basis': scheme.basis,
            'repeat': scheme.repeat,
            'free_product': {'id': scheme.free_product_id.id, 'name': scheme.free_product_id.display_name}
            if scheme.free_product_id else None,
            'slabs': [{'min': slab.min_qty, 'free': slab.free_qty} for slab in scheme.slab_ids.sorted('min_qty')],
        } for scheme in self]


class FfFocSlab(models.Model):
    _name = 'ff.foc.slab'
    _description = 'FOC Slab'
    _order = 'min_qty'

    scheme_id = fields.Many2one('ff.foc.scheme', required=True, ondelete='cascade', index=True)
    min_qty = fields.Float(string='Buy At Least', required=True, default=10)
    free_qty = fields.Float(string='Free Units', required=True, default=1)


def _num(value):
    return int(value) if float(value).is_integer() else value
