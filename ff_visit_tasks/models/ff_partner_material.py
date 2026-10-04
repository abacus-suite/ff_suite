"""Marketing material at each outlet.

Which material an outlet has, how much more it needs and how much has been
supplied to it. The visit asks the first two and the supply task records the
third, so the outlet's own record carries the whole story and nobody has to
add up visits to find out what a shop is short of.
"""
from odoo import api, fields, models


class FfPartnerMaterial(models.Model):
    _name = 'ff.partner.material'
    _description = 'Marketing Material at an Outlet'
    _order = 'partner_id, product_id'

    partner_id = fields.Many2one('res.partner', string='Outlet', required=True, index=True, ondelete='cascade')
    product_id = fields.Many2one('product.product', string='Material', required=True, index=True,
                                 ondelete='cascade')
    available = fields.Boolean(string='Available at Outlet')
    qty_needed = fields.Float(string='Qty Needed', digits=(16, 2),
                              help='What the outlet asks for. It is supplied later by the supply task.')
    qty_supplied = fields.Float(string='Qty Supplied', digits=(16, 2),
                                help='Everything supplied to this outlet so far.')
    qty_outstanding = fields.Float(string='Still to Supply', compute='_compute_outstanding', store=True,
                                   digits=(16, 2))
    last_checked = fields.Datetime(string='Last Checked', readonly=True)
    last_supplied = fields.Datetime(string='Last Supplied', readonly=True)

    _partner_product_uniq = models.Constraint(
        'UNIQUE(partner_id, product_id)', 'This material is already recorded for the outlet.')

    @api.depends('qty_needed', 'qty_supplied')
    def _compute_outstanding(self):
        for row in self:
            row.qty_outstanding = max(row.qty_needed - row.qty_supplied, 0.0)

    @api.model
    def _ff_row(self, partner, product):
        row = self.sudo().search([('partner_id', '=', partner.id), ('product_id', '=', product.id)], limit=1)
        return row or self.sudo().create({'partner_id': partner.id, 'product_id': product.id})

    @api.model
    def ff_record_check(self, partner, rows):
        """A visit's answer: is each material there, and how many are wanted."""
        now = fields.Datetime.now()
        for item in rows or []:
            product = self.env['product.product'].sudo().browse(int(item.get('product_id') or 0)).exists()
            if not product:
                continue
            row = self._ff_row(partner, product)
            row.write({
                'available': bool(item.get('available')),
                'qty_needed': max(float(item.get('qty_needed') or 0), 0.0),
                'last_checked': now,
            })

    @api.model
    def ff_record_supply(self, partner, rows):
        """Material handed over: it adds to what the outlet has been given."""
        now = fields.Datetime.now()
        for item in rows or []:
            product = self.env['product.product'].sudo().browse(int(item.get('product_id') or 0)).exists()
            quantity = float(item.get('qty') or 0)
            if not product or quantity <= 0:
                continue
            row = self._ff_row(partner, product)
            row.write({'qty_supplied': row.qty_supplied + quantity, 'available': True,
                       'last_supplied': now})


class ResPartner(models.Model):
    _inherit = 'res.partner'

    ff_material_ids = fields.One2many('ff.partner.material', 'partner_id', string='Marketing Material')
