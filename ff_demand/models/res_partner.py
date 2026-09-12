from odoo import fields, models


class ResPartner(models.Model):
    _inherit = 'res.partner'

    ff_is_distributor = fields.Boolean(string='Distributor', index=True,
                                       help='Supplies the outlets; the office quotes this partner, not the outlet.')
    ff_distributor_id = fields.Many2one('res.partner', string='Supplied by',
                                        domain=[('ff_is_distributor', '=', True)],
                                        help='Distributor who serves this outlet. Used to group demand.')
