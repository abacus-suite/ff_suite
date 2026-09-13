from odoo import fields, models
from odoo.exceptions import UserError


class FfVisit(models.Model):
    _inherit = 'ff.visit'

    form_response_ids = fields.One2many('ff.form.response', 'visit_id', string='Form Responses')

    def _ff_missing_mandatory_forms(self):
        self.ensure_one()
        visit = self.sudo()
        required = self.env['ff.form']._ff_applicable(visit.employee_id, 'visit', visit.partner_id).filtered('mandatory')
        Response = self.env['ff.form.response']
        return required.filtered(lambda form: not Response.ff_is_filled(visit.employee_id, form, visit.partner_id, visit))

    def ff_check_out(self, data):
        self.ensure_one()
        if self.sudo().state == 'ongoing':
            missing = self._ff_missing_mandatory_forms()
            if missing:
                raise UserError(self.env._('Fill these forms before checking out: %s', ', '.join(missing.mapped('name'))))
        return super().ff_check_out(data)
