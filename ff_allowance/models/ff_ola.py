from datetime import timedelta

from odoo import api, fields, models


class HrEmployee(models.Model):
    _inherit = 'hr.employee'

    ff_ola_applicable = fields.Boolean(
        string='OLA Applicable',
        help='Gets the monthly OLA allowance, paid by the hours worked each day.')
    ff_ola_monthly = fields.Float(
        string='OLA per Month', digits=(10, 2),
        help='The monthly OLA for this employee. Empty (0) uses the company amount in Field Force settings.')


class FfOlaClaim(models.Model):
    """One working day's OLA: the day's rate is the month amount over 26, paid in full, half or not at all by hours."""
    _name = 'ff.ola.claim'
    _description = 'OLA for a Day'
    _order = 'date desc, employee_id'

    employee_id = fields.Many2one('hr.employee', required=True, index=True, ondelete='cascade')
    date = fields.Date(required=True, index=True)
    month = fields.Date(compute='_compute_month', store=True, index=True, help='First day of the month.')
    hours = fields.Float(string='Hours Worked', digits=(6, 2), readonly=True)
    kind = fields.Selection([('none', 'No allowance'), ('half', 'Half'), ('full', 'Full')], readonly=True,
                            default='none')
    day_rate = fields.Monetary(string='Full Day', readonly=True)
    amount = fields.Monetary(readonly=True)
    company_id = fields.Many2one(related='employee_id.company_id', store=True)
    currency_id = fields.Many2one(related='company_id.currency_id')

    _employee_date_uniq = models.Constraint('UNIQUE(employee_id, date)', 'One OLA record per employee and day.')

    @api.depends('date')
    def _compute_month(self):
        for rec in self:
            rec.month = rec.date.replace(day=1) if rec.date else False

    @api.model
    def _ff_params(self):
        get = self.env['ir.config_parameter'].sudo().get_param

        def number(key, default):
            try:
                return float(get('ff_allowance.' + key) or default)
            except ValueError:
                return float(default)

        return {
            'monthly': number('ola_monthly', 1000), 'days': number('ola_days', 26),
            'half': number('ola_half_hours', 4), 'full': number('ola_full_hours', 8),
        }

    @api.model
    def _ff_compute(self, employee, day):
        """Work out OLA for ``employee`` on ``day``; nothing for an employee it does not apply to."""
        employee = employee.sudo()
        if not employee.ff_ola_applicable:
            return self.browse()
        params = self._ff_params()
        start, end = employee._ff_day_bounds(day)
        attendances = self.env['hr.attendance'].sudo().search([
            ('employee_id', '=', employee.id), ('check_in', '>=', start), ('check_in', '<', end),
            ('check_out', '!=', False)])
        if not attendances:
            return self.browse()
        if employee._ff_day_vehicle(day)[1] != 'company':
            return self.browse()  # OLA goes only with a company scooter
        hours = round(sum(attendances.mapped('worked_hours')), 2)
        monthly = employee.ff_ola_monthly or params['monthly']
        per_day = round(monthly / (params['days'] or 26), 2)
        if hours >= params['full']:
            kind, amount = 'full', per_day
        elif hours >= params['half']:
            kind, amount = 'half', round(per_day / 2, 2)
        else:
            kind, amount = 'none', 0.0
        vals = {'hours': hours, 'kind': kind, 'day_rate': per_day, 'amount': amount}
        rec = self.sudo().search([('employee_id', '=', employee.id), ('date', '=', day)], limit=1)
        if rec:
            rec.write(vals)
        else:
            rec = self.sudo().create(dict(vals, employee_id=employee.id, date=day))
        return rec

    @api.model
    def _cron_compute(self):
        since = fields.Datetime.now() - timedelta(days=3)
        employees = self.env['hr.attendance'].sudo().search([('check_in', '>=', since)]).employee_id
        for employee in employees.filtered('ff_ola_applicable'):
            today = employee._ff_today()
            for back in range(0, 4):
                self._ff_compute(employee, today - timedelta(days=back))
