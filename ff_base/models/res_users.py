from odoo import models


class ResUsers(models.Model):
    _inherit = 'res.users'

    def ff_scope_employee_ids(self):
        """Employee ids whose field data this user may see. Used by record rules."""
        self.ensure_one()
        employee = self.sudo().employee_id
        return employee._ff_scope_employees().ids if employee else []
