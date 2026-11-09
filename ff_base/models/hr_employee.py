import logging
import secrets
from datetime import datetime, time, timedelta

import pytz
from passlib.context import CryptContext

from odoo import api, fields, models
from odoo.exceptions import UserError, ValidationError

APP_PASSWORD_CRYPT = CryptContext(['pbkdf2_sha512'])
MIN_PASSWORD_LENGTH = 6
MAX_FAILED_LOGINS = 8
LOCK_MINUTES = 15
RESET_CODE_MINUTES = 10
RESET_RESEND_SECONDS = 60
RESET_MAX_TRIES = 5

_logger = logging.getLogger(__name__)

ACCESS_SCOPES = [
    ('own', 'Own records only'),
    ('hierarchy', 'Direct team members'),
    ('team', 'Team and sub-team access'),
    ('all', 'All employees'),
]
# Changing any of these changes who sees what, and record rule results are cached.
SCOPE_FIELDS = {'ff_access_scope', 'ff_team_id', 'ff_team_ids', 'parent_id', 'user_id', 'active', 'company_id'}


def _normalize_login(vals):
    if 'ff_app_login' in vals:
        vals['ff_app_login'] = (vals['ff_app_login'] or '').strip().lower() or False
    return vals


class HrEmployee(models.Model):
    _inherit = 'hr.employee'

    ff_employee_code = fields.Char(string='Field Employee Code', copy=False, tracking=True)
    # An employee can cover several Regions. ``ff_team_id`` stays as the main (first) one, so everything that reads
    # one Region per employee (reports, dashboards, approval flows) keeps working; ``ff_team_ids`` is the full list.
    ff_team_ids = fields.Many2many('ff.team', 'ff_employee_team_rel', 'employee_id', 'team_id', string='Regions')
    ff_team_id = fields.Many2one('ff.team', string='Main Region', index=True, tracking=True,
                                 help='The first of the Regions: kept in step with the Regions list.')
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
    ff_app_reset_hash = fields.Char(copy=False, groups='base.group_system')
    ff_app_reset_sent = fields.Datetime(copy=False, groups='base.group_system')
    ff_app_reset_tries = fields.Integer(copy=False, groups='base.group_system')
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

    @api.model
    def _ff_region_vals(self, vals):
        """The Regions list and the main Region always agree: choosing one adds it to the other."""
        vals = dict(vals)
        if 'ff_team_ids' in vals and 'ff_team_id' not in vals:
            commands = vals['ff_team_ids'] or []
            ids = []
            for cmd in commands:
                if cmd[0] == 6:
                    ids = list(cmd[2])
                elif cmd[0] == 4:
                    ids.append(cmd[1])
            if ids:
                vals.setdefault('ff_team_id', ids[0])
        elif vals.get('ff_team_id') and 'ff_team_ids' not in vals:
            vals['ff_team_ids'] = [(4, vals['ff_team_id'])]
        return vals

    @api.model_create_multi
    def create(self, vals_list):
        employees = super().create([_normalize_login(self._ff_region_vals(vals)) for vals in vals_list])
        self.env.registry.clear_cache()
        return employees

    def write(self, vals):
        vals = self._ff_region_vals(vals)
        res = super().write(_normalize_login(vals))
        if 'ff_team_ids' in vals:
            # Whatever the list ends up as, the main Region is one of them (the first when it was removed).
            for employee in self:
                regions = employee.ff_team_ids
                if employee.ff_team_id not in regions:
                    employee.ff_team_id = regions[:1]
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
            # Direct team members: the people whose Manager is this employee.
            return employee | Employee.search([('parent_id', '=', employee.id)])
        if scope == 'team':
            # Team and sub-team access: the whole chain below, by the Manager field only.
            return Employee.search([('id', 'child_of', employee.ids)])
        return employee

    def _ff_subordinates(self):
        """Employees ``self`` may supervise and approve for (never self)."""
        if not self or self.sudo().ff_access_scope == 'own':
            return self.browse()
        return self._ff_scope_employees() - self

    def _ff_approval_team(self):
        """Who ``self`` approves for: the people in their data access, and always their direct reports (the
        manager an employee's request is sent to), whatever the data access says."""
        direct = self.env['hr.employee'].sudo().search([('parent_id', 'in', self.ids)]) if self else self.browse()
        return (self._ff_subordinates() | direct) - self

    def _ff_is_manager_of(self, employee):
        self.ensure_one()
        return employee in self._ff_approval_team()

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

    # ------------------------------------------------------------------
    # Forgot / change password from the app
    # ------------------------------------------------------------------
    @api.model
    def ff_app_request_reset(self, login):
        """Email a one-time code to the employee behind this app login.

        Says nothing about whether the login exists, so it cannot be used to find out who has the app.
        """
        login = (login or '').strip().lower()
        employee = self.sudo().search(
            [('ff_app_login', '=', login), ('ff_app_access', '=', True)], limit=1) if login else self.sudo().browse()
        if not employee:
            return
        now = fields.Datetime.now()
        if employee.ff_app_reset_sent and (now - employee.ff_app_reset_sent).total_seconds() < RESET_RESEND_SECONDS:
            return
        email = (employee.work_email or employee.user_id.email or '').strip()
        if not email:
            _logger.warning('App password reset for %s: no work email on the employee.', employee.display_name)
            return
        code = '%06d' % secrets.randbelow(1000000)
        employee.write({'ff_app_reset_hash': APP_PASSWORD_CRYPT.hash(code),
                        'ff_app_reset_sent': now, 'ff_app_reset_tries': 0})
        body = self.env._(
            '<p>Hello %(name)s,</p><p>Your Field Force app password reset code is '
            '<b style="font-size:18px;letter-spacing:3px">%(code)s</b>.</p>'
            '<p>It works for %(minutes)s minutes. If you did not ask for it, ignore this email.</p>',
            name=employee.name, code=code, minutes=RESET_CODE_MINUTES)
        try:
            self.env['mail.mail'].sudo().create({
                'subject': self.env._('Field Force app: password reset code'),
                'body_html': body, 'email_to': email, 'auto_delete': True,
            }).send()
        except Exception:
            _logger.exception('Could not send the app password reset code to %s', employee.display_name)

    @api.model
    def ff_app_confirm_reset(self, login, code, new_password):
        login = (login or '').strip().lower()
        employee = self.sudo().search(
            [('ff_app_login', '=', login), ('ff_app_access', '=', True)], limit=1) if login else self.sudo().browse()
        bad = UserError(self.env._('That code is not right or has expired. Ask for a new one.'))
        if not employee or not employee.ff_app_reset_hash or not employee.ff_app_reset_sent:
            APP_PASSWORD_CRYPT.dummy_verify()
            raise bad
        expired = (fields.Datetime.now() - employee.ff_app_reset_sent) > timedelta(minutes=RESET_CODE_MINUTES)
        if expired or employee.ff_app_reset_tries >= RESET_MAX_TRIES:
            employee.write({'ff_app_reset_hash': False})
            raise bad
        if not APP_PASSWORD_CRYPT.verify((code or '').strip(), employee.ff_app_reset_hash):
            employee.write({'ff_app_reset_tries': employee.ff_app_reset_tries + 1})
            raise bad
        employee.ff_set_app_password(new_password)
        employee.write({'ff_app_reset_hash': False, 'ff_app_reset_sent': False, 'ff_app_reset_tries': 0})
        employee.ff_app_token_ids.unlink()  # signed in anywhere else: sign in again with the new password
        return employee

    def ff_app_change_password(self, current_password, new_password, keep_token=None):
        """Change the password while signed in; other sessions are signed out."""
        self.ensure_one()
        employee = self.sudo()
        if not employee.ff_app_password_hash or not APP_PASSWORD_CRYPT.verify(
                current_password or '', employee.ff_app_password_hash):
            raise UserError(self.env._('Your current password is not right.'))
        if current_password == new_password:
            raise UserError(self.env._('Choose a password different from the current one.'))
        employee.ff_set_app_password(new_password)
        (employee.ff_app_token_ids - (keep_token or employee.ff_app_token_ids.browse())).unlink()

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
        calendar_tz = self.resource_calendar_id.tz if self.resource_calendar_id else False
        name = self.tz if self.tz and self.tz != 'UTC' else (
            self.env['ir.config_parameter'].sudo().get_param('ff_base.default_tz')
            # The timezone of the employee's working hours (for example Asia/Kolkata), before the company's.
            or (calendar_tz if calendar_tz and calendar_tz != 'UTC' else False)
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
