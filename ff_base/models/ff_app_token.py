import hashlib
import secrets
from datetime import timedelta

from odoo import api, fields, models

TOKEN_DAYS = 90
TOUCH_MINUTES = 5


def _hash(raw):
    return hashlib.sha256(raw.encode()).hexdigest()


class FfAppToken(models.Model):
    """Mobile app session. Only a SHA-256 hash of the token is stored."""
    _name = 'ff.app.token'
    _description = 'Mobile App Session'
    _order = 'last_used_at desc, id desc'

    employee_id = fields.Many2one('hr.employee', required=True, index=True, ondelete='cascade')
    name = fields.Char(string='Device')
    device_uid = fields.Char(string='Device ID', index=True)
    token_hash = fields.Char(required=True, index=True, copy=False, groups='base.group_system')
    expires_at = fields.Datetime(string='Expires', required=True)
    last_used_at = fields.Datetime(string='Last Used')

    _token_hash_uniq = models.Constraint('UNIQUE(token_hash)', 'Duplicate session token.')

    @api.model
    def ff_issue(self, employee, device_uid, device_name=None):
        """New session for ``employee`` on ``device_uid``. Returns (raw token, expiry)."""
        Token = self.sudo()
        Token.search([('employee_id', '=', employee.id), ('device_uid', '=', device_uid)]).unlink()
        raw = secrets.token_urlsafe(48)
        now = fields.Datetime.now()
        token = Token.create({
            'employee_id': employee.id,
            'device_uid': device_uid,
            'name': device_name or False,
            'token_hash': _hash(raw),
            'expires_at': now + timedelta(days=TOKEN_DAYS),
            'last_used_at': now,
        })
        return raw, token.expires_at

    @api.model
    def ff_resolve(self, raw):
        """Valid session for a raw bearer token, else an empty recordset."""
        if not raw:
            return self.browse()
        now = fields.Datetime.now()
        token = self.sudo().search([('token_hash', '=', _hash(raw)), ('expires_at', '>', now)], limit=1)
        employee = token.employee_id
        if not token or not employee.active or not employee.ff_app_access:
            return self.browse()
        if not token.last_used_at or now - token.last_used_at > timedelta(minutes=TOUCH_MINUTES):
            token.last_used_at = now
        return token

    @api.model
    def _cron_purge_expired(self):
        self.sudo().search([('expires_at', '<', fields.Datetime.now())]).unlink()
