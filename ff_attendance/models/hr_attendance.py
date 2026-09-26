from odoo import api, fields, models

VEHICLES = [
    ('two_wheeler', 'Two-wheeler'),
    ('four_wheeler', 'Four-wheeler'),
    ('public', 'Public transport'),
    ('walk', 'On foot'),
    ('other', 'Other'),
]


DAY_STATUSES = [
    ('present', 'Present'),
    ('late', 'Late'),
    ('half_day', 'Half Day'),
]


class HrAttendance(models.Model):
    _inherit = 'hr.attendance'

    ff_source = fields.Selection([
        ('web', 'Web / Kiosk'),
        ('app', 'Mobile App'),
        ('regularisation', 'Regularisation'),
    ], string='Source', default='web')
    ff_shift_id = fields.Many2one('ff.shift', string='Shift')
    ff_in_address = fields.Char(string='Punch-in Address')
    ff_offline = fields.Boolean(string='Recorded Offline', readonly=True,
                                help='Punched without network; the app sent it later with the real time.')
    ff_in_uuid = fields.Char(index=True, copy=False)
    ff_out_uuid = fields.Char(index=True, copy=False)
    ff_out_address = fields.Char(string='Punch-out Address')
    ff_vehicle_type = fields.Selection(
        VEHICLES, string='Vehicle', help='How the person travelled on this day, chosen at check-in.')
    ff_vehicle_note = fields.Char(
        string='Vehicle Note', help='What "Other" was: a lift, a hired vehicle, a company van...')
    ff_in_odometer = fields.Float(string='Odometer at Punch-in', digits=(12, 1))
    ff_out_odometer = fields.Float(string='Odometer at Punch-out', digits=(12, 1))
    ff_in_odometer_photo = fields.Image(string='Odometer Photo (in)', max_width=1280, max_height=1280)
    ff_out_odometer_photo = fields.Image(string='Odometer Photo (out)', max_width=1280, max_height=1280)
    ff_odometer_km = fields.Float(string='Odometer km', compute='_compute_ff_odometer_km', store=True, digits=(12, 1),
                                  help='Punch-out reading less the punch-in reading.')
    ff_in_selfie = fields.Image(string='Punch-in Selfie', max_width=1024, max_height=1024)
    ff_out_selfie = fields.Image(string='Punch-out Selfie', max_width=1024, max_height=1024)
    ff_in_accuracy = fields.Float(string='Punch-in Accuracy (m)')
    ff_out_accuracy = fields.Float(string='Punch-out Accuracy (m)')
    ff_in_is_mock = fields.Boolean(string='Punch-in Mock Location')
    ff_out_is_mock = fields.Boolean(string='Punch-out Mock Location')
    ff_late_minutes = fields.Integer(string='Late (min)', compute='_compute_ff_day_status', store=True)
    ff_day_status = fields.Selection(DAY_STATUSES, string='Day Status', compute='_compute_ff_day_status', store=True)

    @api.depends('ff_in_odometer', 'ff_out_odometer')
    def _compute_ff_odometer_km(self):
        for att in self:
            both = att.ff_in_odometer and att.ff_out_odometer
            att.ff_odometer_km = max(att.ff_out_odometer - att.ff_in_odometer, 0.0) if both else 0.0

    @api.depends('check_in', 'check_out', 'worked_hours', 'ff_shift_id')
    def _compute_ff_day_status(self):
        for att in self:
            shift = att.ff_shift_id
            late = 0
            if shift and att.check_in and att.employee_id:
                local_in = att.employee_id._ff_to_local(att.check_in)
                hours, minutes = divmod(shift._ff_start_minutes(), 60)
                start = local_in.replace(hour=hours, minute=minutes, second=0, microsecond=0)
                late = max(0, int((local_in - start).total_seconds() // 60))
            att.ff_late_minutes = late
            if shift and att.check_out and att.worked_hours < shift.half_day_hours:
                att.ff_day_status = 'half_day'
            elif shift and late > shift.grace_minutes:
                att.ff_day_status = 'late'
            else:
                att.ff_day_status = 'present'

    @api.model_create_multi
    def create(self, vals_list):
        for vals in vals_list:
            if not vals.get('ff_shift_id') and vals.get('employee_id'):
                employee = self.env['hr.employee'].sudo().browse(vals['employee_id'])
                vals['ff_shift_id'] = employee.ff_shift_id.id
        records = super().create(vals_list)
        records.employee_id._ff_sync_punch_status()
        return records

    def write(self, vals):
        employees = self.employee_id
        res = super().write(vals)
        if {'check_in', 'check_out', 'employee_id'} & set(vals):
            (employees | self.employee_id)._ff_sync_punch_status()
        return res

    def unlink(self):
        employees = self.employee_id
        res = super().unlink()
        employees.exists()._ff_sync_punch_status()
        return res
