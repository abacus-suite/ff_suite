from odoo import fields, models
from odoo.exceptions import ValidationError


class FfAppPasswordWizard(models.TransientModel):
    _name = 'ff.app.password.wizard'
    _description = 'Set Mobile App Password'

    employee_id = fields.Many2one('hr.employee', required=True, readonly=True)
    # Not required at model level: the clear-text values are wiped after saving.
    login = fields.Char(string='App Login')
    password = fields.Char()
    confirm_password = fields.Char()
    logout_devices = fields.Boolean(string='Log Out Existing Devices', default=True)

    def action_apply(self):
        self.ensure_one()
        if not (self.login or '').strip():
            raise ValidationError(self.env._('Enter an app login.'))
        if not self.password:
            raise ValidationError(self.env._('Enter a password.'))
        if self.password != self.confirm_password:
            raise ValidationError(self.env._('The passwords do not match.'))
        employee = self.employee_id.sudo()
        employee.write({'ff_app_login': self.login, 'ff_app_access': True})
        employee.ff_set_app_password(self.password)
        if self.logout_devices:
            employee.ff_app_token_ids.unlink()
        # Do not keep the clear-text password in the transient table.
        self.write({'password': False, 'confirm_password': False})
        return {
            'type': 'ir.actions.client',
            'tag': 'display_notification',
            'params': {
                'type': 'success',
                'message': self.env._('App login "%(login)s" is ready for %(name)s.',
                                      login=employee.ff_app_login, name=employee.name),
                'next': {'type': 'ir.actions.act_window_close'},
            },
        }
