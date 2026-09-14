from datetime import datetime, time, timedelta

import pytz
from passlib.context import CryptContext

from odoo import api, fields, models
from odoo.exceptions import UserError, ValidationError

APP_PASSWORD_CRYPT = CryptContext(['pbkdf2_sha512'])
MIN_PASSWORD_LENGTH = 6
MAX_FAILED_LOGINS = 8
LOCK_MINUTES = 15

ACCESS_SCOPES = [
    ('own', 'Own records only'),
    ('hierarchy', 'Employees reporting to them'),
    ('team', 'Their field team (incl. sub-teams)'),
    ('all', 'All employees'),
]
# Changing any of these changes who sees what, and record rule results are cached.
SCOPE_FIELDS = {'ff_access_scope', 'ff_team_id', 'parent_id', 'user_id', 'active', 'company_id'}


def _normalize_login(vals):
    if 'ff_app_login' in vals:
        vals['ff_app_login'] = (vals['ff_app_login'] or '').strip().lower() or False
    return vals


class HrEmployee(models.Model):
    _inherit = 'hr.employee'

    ff_employee_code = fields.Char(string='Field Employee Code', copy=False, tracking=True)
    ff_team_id = fields.Many2one('ff.team', string='Field Team', index=True, tracking=True)
    ff_designation_id = fields.Many2one('ff.designation', string='Field Designation', tracking=True)
    ff_tracking_enabled = fields.Boolean(
        string='Location Tracking', default=True,
        help='Track GPS location from the mobile app while the employee is punched in.',
    )
    ff_device_ids = fields.One2many('ff.device', 'employee_id', string='Devices')

    ff_access_scope = fields.Selection(
        ACCESS_SCOPES, string='Data Access', default='own', required=True, tracking=True,
        groups='ff_base.group_ff_admin',
        help="Whose field data this person sees and can approve, in Odoo and in the mobile app.")
    ff_app_access = fields.Boolean(string='Mobile App Access', tracking=True, groups='ff_base.group_ff_admin')
    ff_app_login = fields.Char(string='App Login', copy=False, index=True, groups='ff_base.group_ff_admin')
    ff_app_password_hash = fields.Char(copy=False, groups='base.group_system')
    ff_app_password_set = fields.Boolean(string='App Password Set', compute='_compute_ff_app_password_set',
                                         groups='ff_base.group_ff_admin')
    ff_app_failed_logins = fields.Integer(copy=False, groups='base.group_system')
    ff_app_locked_until = fields.Datetime(string='App Locked Until', copy=False, groups='ff_base.group_ff_admin')
    ff_app_last_login = fields.Datetime(string='Last App Login', copy=False, readonly=True,
                                        groups='ff_base.group_ff_admin')
    ff_app_token_ids = fields.One2many('ff.app.token', 'employee_id', string='App Sessions',
                                       groups='ff_base.group_ff_admin')

    _ff_employee_code_uniq = models.Constraint(
        'UNIQUE(ff_employee_code, company_id)',
        'The field employee code must be unique per company.',
    )
    _ff_app_login_uniq = models.Constraint(
        'UNIQUE(ff_app_login, company_id)',
        'This app login is already used by another employee.',
    )

    def _compute_ff_app_password_set(self):
        for employee in self:
            employee.ff_app_password_set = bool(employee.sudo().ff_app_password_hash)

    @api.model_create_multi
    def create(self, vals_list):
        employees = super().create([_normalize_login(vals) for vals in vals_list])
        self.env.registry.clear_cache()
        return employees

    def write(self, vals):
        res = super().write(_normalize_login(vals))
        if SCOPE_FIELDS & set(vals):
            self.env.registry.clear_cache()
        if vals.get('ff_app_access') is False:
            self.sudo().ff_app_token_ids.unlink()
        return res

    # ------------------------------------------------------------------
    # Data access scope
    # ------------------------------------------------------------------
    def _ff_scope_employees(self):
        """Employees whose field data ``self`` may see (always includes self)."""
        self.ensure_one()
        employee = self.sudo()
        Employee = self.env['hr.employee'].sudo()
        scope = employee.ff_access_scope
        if scope == 'all':
            return Employee.search([('company_id', 'in', employee.company_id.ids)])
        if scope == 'hierarchy':
            return Employee.search([('id', 'child_of', employee.ids)])
        if scope == 'team' and employee.ff_team_id:
            return employee | Employee.search([('ff_team_id', 'child_of', employee.ff_team_id.ids)])
        return employee

    def _ff_subordinates(self):
        """Employees ``self`` may supervise and approve for (never self)."""
        if not self or self.sudo().ff_access_scope == 'own':
            return self.browse()
        return self._ff_scope_employees() - self

    def _ff_is_manager_of(self, employee):
        self.ensure_one()
        return employee in self._ff_subordinates()

    # ------------------------------------------------------------------
    # Mobile app credentials (independent of Odoo user accounts)
    # ------------------------------------------------------------------
    def ff_set_app_password(self, password):
        self.ensure_one()
        if not password or len(password) < MIN_PASSWORD_LENGTH:
            raise ValidationError(self.env._('The app password needs at least %s characters.', MIN_PASSWORD_LENGTH))
        self.sudo().write({
            'ff_app_password_hash': APP_PASSWORD_CRYPT.hash(password),
            'ff_app_failed_logins': 0,
            'ff_app_locked_until': False,
        })

    @api.model
    def ff_app_authenticate(self, login, password):
        """Employee for valid app credentials, else an empty recordset.

        Raises UserError while the account is locked after repeated failures.
        """
        login = (login or '').strip().lower()
        employee = self.sudo().search(
            [('ff_app_login', '=', login), ('ff_app_access', '=', True)], limit=1) if login else self.sudo().browse()
        if not employee or not employee.ff_app_password_hash:
            APP_PASSWORD_CRYPT.dummy_verify()  # same timing as a real check
            return self.browse()
        now = fields.Datetime.now()
        if employee.ff_app_locked_until and employee.ff_app_locked_until > now:
            minutes = int((employee.ff_app_locked_until - now).total_seconds() // 60) + 1
            raise UserError(self.env._('Too many failed attempts. Try again in %s minutes.', minutes))
        if not APP_PASSWORD_CRYPT.verify(password or '', employee.ff_app_password_hash):
            failed = employee.ff_app_failed_logins + 1
            if failed >= MAX_FAILED_LOGINS:
                employee.write({'ff_app_failed_logins': 0,
                                'ff_app_locked_until': now + timedelta(minutes=LOCK_MINUTES)})
            else:
                employee.write({'ff_app_failed_logins': failed})
            return self.browse()
        employee.write({'ff_app_failed_logins': 0, 'ff_app_locked_until': False, 'ff_app_last_login': now})
        return employee

    def action_ff_set_app_password(self):
        self.ensure_one()
        return {
            'type': 'ir.actions.act_window',
            'name': self.env._('Set App Password'),
            'res_model': 'ff.app.password.wizard',
            'view_mode': 'form',
            'target': 'new',
            'context': {
                'default_employee_id': self.id,
                'default_login': self.sudo().ff_app_login or self.work_email or self.ff_employee_code,
            },
        }

    def action_ff_revoke_sessions(self):
        self.sudo().ff_app_token_ids.unlink()

    # ------------------------------------------------------------------
    # Timezone helpers: Odoo stores naive UTC, the field day is local.
    # ------------------------------------------------------------------
    def _ff_tz(self):
        """The employee's local timezone.

        An empty timezone, or the UTC that Odoo fills in by default, would put
        an Indian morning on the previous day - so those fall back to the
        field timezone in Field Force settings, then the company's.
        """
        self.ensure_one()
        name = self.tz if self.tz and self.tz != 'UTC' else (
            self.env['ir.config_parameter'].sudo().get_param('ff_base.default_tz')
            or self.company_id.partner_id.tz or self.tz or 'UTC')
        try:
            return pytz.timezone(name)
        except pytz.UnknownTimeZoneError:
            return pytz.utc

    def _ff_today(self):
        return datetime.now(pytz.utc).astimezone(self._ff_tz()).date()

    def _ff_to_local(self, dt):
        return pytz.utc.localize(dt).astimezone(self._ff_tz()).replace(tzinfo=None)

    def _ff_day_bounds(self, day):
        """Naive-UTC [start, end) of the local calendar ``day``."""
        tz = self._ff_tz()
        start = tz.localize(datetime.combine(day, time.min)).astimezone(pytz.utc)
        end = tz.localize(datetime.combine(day + timedelta(days=1), time.min)).astimezone(pytz.utc)
        return start.replace(tzinfo=None), end.replace(tzinfo=None)
