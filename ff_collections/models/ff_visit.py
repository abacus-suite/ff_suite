from odoo import api, fields, models

from odoo.addons.ff_base.tools import get_param


class FfVisit(models.Model):
    _inherit = 'ff.visit'

    collection_ids = fields.One2many('ff.collection', 'visit_id', string='Collections')
    collected_amount = fields.Monetary(compute='_compute_collected', store=True)
    currency_id = fields.Many2one(related='employee_id.company_id.currency_id')

    @api.depends('collection_ids.amount', 'collection_ids.state')
    def _compute_collected(self):
        for visit in self:
            visit.collected_amount = sum(
                visit.collection_ids.filtered(lambda c: c.state != 'cancelled').mapped('amount'))

    @api.model
    def ff_check_in(self, employee, partner, data):
        """Block a new visit while the employee holds money past the office limits."""
        if get_param(self.env, 'payment_collection'):
            self.env['ff.collection']._ff_check_deposit_due(employee)
        return super().ff_check_in(employee, partner, data)
