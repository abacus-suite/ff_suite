from odoo import fields, models


class FfTerritory(models.Model):
    _inherit = 'ff.territory'

    ff_mrp_id = fields.Many2one(
        'ff.partner.option', string='MRP', domain=[('kind', '=', 'mrp')],
        help='The MRP of the outlets and distributors in this territory. The app picks it by itself when one of '
             'them is onboarded here (it can still be changed).')

    def ff_mrp_option(self):
        """The MRP option of this territory: the one set on it, else the one named like its price category."""
        self.ensure_one()
        if self.ff_mrp_id:
            return self.ff_mrp_id
        if self.ff_price_category:
            return self.env['ff.partner.option'].sudo().search(
                [('kind', '=', 'mrp'), ('name', '=', self.ff_price_category)], limit=1)
        return self.env['ff.partner.option']
