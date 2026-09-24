from odoo import fields, models
from odoo.exceptions import UserError

from odoo.addons.ff_base.tools import get_param


class FfVisit(models.Model):
    _inherit = 'ff.visit'

    step_record_ids = fields.One2many('ff.visit.step.record', 'visit_id', string='Steps')
    stock_count_ids = fields.One2many('ff.stock.count', 'visit_id', string='Stock Counts')

    def _ff_missing_steps(self):
        """Mandatory steps that are still open for this visit."""
        self.ensure_one()
        if not get_param(self.env, 'visit_steps'):
            return self.env['ff.visit.step']
        visit = self.sudo()
        required = self.env['ff.visit.step'].ff_for(visit.employee_id, visit.partner_id).filtered('mandatory')
        return required - visit.step_record_ids.step_id

    def ff_check_out(self, data):
        self.ensure_one()
        if self.sudo().state == 'ongoing':
            missing = self._ff_missing_steps()
            if missing:
                raise UserError(self.env._('Finish these steps before checking out: %s',
                                           ', '.join(missing.mapped('name'))))
        return super().ff_check_out(data)
