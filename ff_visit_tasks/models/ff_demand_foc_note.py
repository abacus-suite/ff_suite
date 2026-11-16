"""Free goods sent to a distributor are covered by a debit note.

The distributor hands the free goods to the outlet out of its own stock, so when the demand goes
to the distributor a debit note is raised for those products: the company makes the distributor
good for them. A distributor that turns the request down does not owe or get anything, so the
note is rejected with it.
"""
from odoo import api, fields, models

PREFIX = 'Free goods (FOC)'


class FfDemand(models.Model):
    _inherit = 'ff.demand'

    note_ids = fields.One2many('ff.distributor.note', 'demand_id', string='Credit / Debit Notes')
    note_count = fields.Integer(compute='_compute_note_count')

    def _compute_note_count(self):
        for demand in self:
            demand.note_count = len(demand.note_ids)

    def action_open_notes(self):
        self.ensure_one()
        return {
            'type': 'ir.actions.act_window', 'name': self.env._('Credit / Debit Notes'),
            'res_model': 'ff.distributor.note', 'view_mode': 'list,form',
            'domain': [('demand_id', '=', self.id)],
        }

    def _ff_foc_note(self, distributor=None):
        """Raise the debit note for this demand's free goods, once. Returns it, or nothing when there is none to raise."""
        self.ensure_one()
        distributor = distributor or self.distributor_id
        free = self.line_ids.filtered(lambda l: getattr(l, 'is_foc', False) and l.quantity)
        Note = self.env['ff.distributor.note'].sudo()
        if not free or not distributor:
            return Note
        # A sample collection's free demand is covered by its credit note: never a free-goods debit note as well, whether
        # or not that credit note exists yet or is still waiting.
        if Note.search_count([('demand_id', '=', self.id), ('source', '=', 'sample'), ('state', '!=', 'rejected')])                 or self.env['ff.task.log'].sudo().search_count([('demand_ids', 'in', self.ids),
                                                                 ('sample_source', '=', 'outlet')]):
            return Note
        if Note.search_count([('demand_id', '=', self.id), ('kind', '=', 'debit'),
                              ('reason', 'like', PREFIX), ('state', '!=', 'rejected')]):
            return Note
        rows = [{'product_id': l.product_id.id, 'qty': l.quantity} for l in free]
        note = Note.ff_raise(
            self.employee_id, 'debit', rows, distributor=distributor, partner=self.partner_id,
            reason='%s on %s' % (PREFIX, self.name), demand=self, source='foc')
        return note

    def action_ff_foc_note(self):
        """By hand, for a demand sent before this was automatic."""
        for demand in self:
            demand._ff_foc_note()
        return True

    def ff_foc_request(self, employee, distributor=None):
        # Asking the distributor for the free goods from the app (a message, no order) also raises the debit note.
        result = super().ff_foc_request(employee, distributor)
        self._ff_foc_note(distributor or self.distributor_id)
        return result

    def ff_foc_deliver(self, note=None):
        # Delivered without a note raised yet (asked before this was automatic): raise it now.
        result = super().ff_foc_deliver(note)
        for demand in self:
            demand._ff_foc_note()
        return result

    def _ff_make_request(self, distributor, employee=None):
        request = super()._ff_make_request(distributor, employee)
        for demand in self:
            demand._ff_foc_note(distributor)
            # A sample collection's credit note follows the distributor it is sent to, again or to another.
            self.env['ff.distributor.note'].sudo().search([('demand_id', '=', demand.id)]).ff_sample_reassign(distributor)
        return request

    def write(self, vals):
        result = super().write(vals)
        if vals.get('state') == 'rejected':
            self.env['ff.distributor.note'].sudo().search([('demand_id', 'in', self.ids)]).ff_sample_cancel()
        return result


class FfDemandDelivery(models.Model):
    _inherit = 'ff.demand.delivery'

    @api.model_create_multi
    def create(self, vals_list):
        deliveries = super().create(vals_list)
        # Free goods that reach an outlet are covered by a debit note even if the demand went out before
        # notes were raised on sending.
        for delivery in deliveries:
            if delivery.line_ids.filtered(lambda l: getattr(l.demand_line_id, 'is_foc', False)):
                delivery.demand_id._ff_foc_note()
        return deliveries


class FfDemandRequest(models.Model):
    _inherit = 'ff.demand.request'

    def ff_reject(self, note=None):
        result = super().ff_reject(note)
        self.env['ff.distributor.note'].sudo().search([
            ('demand_id', 'in', self.demand_ids.ids), ('kind', '=', 'debit'),
            ('reason', 'like', PREFIX), ('state', '=', 'pending')]).write({'state': 'rejected'})
        return result
