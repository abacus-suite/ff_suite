from odoo import api, fields, models


class FfDemandDeliveryWizard(models.TransientModel):
    _name = 'ff.demand.delivery.wizard'
    _description = 'Record a Delivery'

    demand_id = fields.Many2one('ff.demand', required=True, ondelete='cascade')
    note = fields.Char()
    line_ids = fields.One2many('ff.demand.delivery.wizard.line', 'wizard_id')

    @api.model
    def default_get(self, fields_list):
        values = super().default_get(fields_list)
        demand = self.env['ff.demand'].browse(values.get('demand_id') or self.env.context.get('default_demand_id'))
        if demand:
            values['demand_id'] = demand.id
            values['line_ids'] = [(0, 0, {
                'line_id': line.id, 'approved': line.approved_quantity, 'delivered': line.delivered_quantity,
                'quantity': max(line.approved_quantity - line.delivered_quantity, 0.0),
            }) for line in demand.line_ids if line.approved_quantity > 0]
        return values

    def action_record(self):
        self.ensure_one()
        self.demand_id.ff_record_delivery(
            {row.line_id.id: row.quantity for row in self.line_ids}, note=self.note,
            entered_by=self.env.user.name)
        return {'type': 'ir.actions.act_window_close'}


class FfDemandDeliveryWizardLine(models.TransientModel):
    _name = 'ff.demand.delivery.wizard.line'
    _description = 'Record a Delivery Line'

    wizard_id = fields.Many2one('ff.demand.delivery.wizard', required=True, ondelete='cascade')
    line_id = fields.Many2one('ff.demand.line', required=True)
    product_id = fields.Many2one(related='line_id.product_id')
    approved = fields.Float()
    delivered = fields.Float()
    quantity = fields.Float(string='Delivering Now')
