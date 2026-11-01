from odoo import fields, models


class FfDistributorNote(models.Model):
    _inherit = 'ff.distributor.note'

    margin_excess = fields.Float(string='Excess Margin %', digits=(5, 2))
    delivery_id = fields.Many2one('ff.demand.delivery', string='Delivery', ondelete='set null', index=True)
