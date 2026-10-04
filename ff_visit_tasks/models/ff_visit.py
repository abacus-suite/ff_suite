from odoo import api, fields, models


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
