from odoo import api, fields, models
from odoo.exceptions import UserError


class FfVisit(models.Model):
    _inherit = 'ff.visit'

    task_code = fields.Char(string='Task', index=True, readonly=True,
                            help='Which task this visit was opened for.')

    @api.model
    def ff_check_in(self, employee, partner, data):
        visit = super().ff_check_in(employee, partner, data)
        if data.get('task') and not visit.task_code:
            visit.sudo().task_code = data['task']
        return visit

    def ff_check_out(self, data):
        """A visit opened for a task ends when the task is submitted, and not before."""
        for visit in self.sudo().filtered(lambda v: v.state == 'ongoing' and v.task_code):
            if not data.get('task') and not data.get('auto'):
                raise UserError(self.env._('Finish and submit the %s task to check out.',
                                           visit.task_code.replace('_', ' ')))
        return super().ff_check_out(data)
