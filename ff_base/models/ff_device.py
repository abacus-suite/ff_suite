from odoo import api, fields, models


class FfDevice(models.Model):
    _name = 'ff.device'
    _description = 'Field Staff Mobile Device'
    _order = 'last_seen desc'

    name = fields.Char(string='Device Model')
    employee_id = fields.Many2one('hr.employee', required=True, index=True, ondelete='cascade')
    device_uid = fields.Char(string='Device ID', required=True, index=True)
    os_version = fields.Char(string='OS Version')
    app_version = fields.Char()
    fcm_token = fields.Char(string='Push Token')
    last_seen = fields.Datetime()
    active = fields.Boolean(default=True)

    _employee_device_uniq = models.Constraint(
        'UNIQUE(employee_id, device_uid)',
        'This device is already registered for the employee.',
    )

    @api.model
    def ff_register(self, employee, vals):
        """Create or refresh the device record of ``employee`` (sudo)."""
        device_uid = vals.get('device_uid')
        if not device_uid:
            return self.browse()
        Device = self.sudo().with_context(active_test=False)
        device = Device.search([('employee_id', '=', employee.id), ('device_uid', '=', device_uid)], limit=1)
        data = {
            'active': True,
            'last_seen': fields.Datetime.now(),
        }
        for key in ('name', 'os_version', 'app_version', 'fcm_token'):
            if vals.get(key):
                data[key] = vals[key]
        # A push token belongs to one phone login at a time: a phone shared by several
        # people (or an app that was not logged out) must not keep notifying the others.
        token = data.get('fcm_token')
        if token:
            Device.search([('fcm_token', '=', token),
                           '|', ('employee_id', '!=', employee.id), ('device_uid', '!=', device_uid)]
                          ).write({'fcm_token': False})
        else:
            # Same phone, new login without a token yet: older logins on it lose theirs.
            Device.search([('device_uid', '=', device_uid), ('employee_id', '!=', employee.id),
                           ('fcm_token', '!=', False)]).write({'fcm_token': False})
        if device:
            device.write(data)
        else:
            device = Device.create(dict(data, employee_id=employee.id, device_uid=device_uid))
        return device
