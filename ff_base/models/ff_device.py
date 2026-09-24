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
        if device:
            device.write(data)
        else:
            device = Device.create(dict(data, employee_id=employee.id, device_uid=device_uid))
        return device
