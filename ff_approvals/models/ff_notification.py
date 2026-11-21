"""What the app shows in its bell and delivers to the phone via Firebase Cloud Messaging.

Odoo tells people through the chatter and their activity list, which works at a
desk. A field officer lives in the app, so the same news is written here as
well: one row per person per event, read when they open it, and pushed to their
mobile device status bar via Firebase Cloud Messaging (FCM).
"""
import base64
from datetime import timedelta
import json
import logging
import os
import time
import urllib.error
import urllib.parse
import urllib.request

from odoo import api, fields, models

_logger = logging.getLogger(__name__)

KINDS = [
    ('approval', 'Waiting for you'),
    ('decision', 'Decision on your request'),
    ('info', 'Information'),
]

# In-memory cache for OAuth2 access token: (token, expiry_timestamp, project_id)
_FCM_TOKEN_CACHE = None


def _get_fcm_access_token(env):
    global _FCM_TOKEN_CACHE
    now = int(time.time())
    if _FCM_TOKEN_CACHE and _FCM_TOKEN_CACHE[1] > now + 60:
        return _FCM_TOKEN_CACHE[0], _FCM_TOKEN_CACHE[2]

    key_data = None
    # 1. Check ir.config_parameter
    sa_param = env['ir.config_parameter'].sudo().get_param('ff.firebase_service_account')
    if sa_param:
        try:
            key_data = json.loads(sa_param)
        except Exception:
            _logger.warning("Invalid JSON in ff.firebase_service_account parameter")

    # 2. Check file candidates if not in ir.config_parameter
    if not key_data:
        cur_dir = os.path.dirname(os.path.abspath(__file__))
        candidates = [
            env['ir.config_parameter'].sudo().get_param('ff.firebase_service_account_path'),
            os.path.join(os.path.dirname(cur_dir), 'data', 'firebase_service_account.json'),
            os.path.join(os.path.dirname(os.path.dirname(cur_dir)), 'ff_base', 'data', 'firebase_service_account.json'),
        ]
        for candidate in candidates:
            if candidate and os.path.isfile(candidate):
                try:
                    with open(candidate, 'r', encoding='utf-8') as f:
                        key_data = json.load(f)
                    if key_data and 'client_email' in key_data:
                        try:
                            env['ir.config_parameter'].sudo().set_param('ff.firebase_service_account', json.dumps(key_data))
                        except Exception:
                            pass
                        break
                except Exception as e:
                    _logger.warning("Error reading service account from %s: %s", candidate, e)

    if not key_data or 'client_email' not in key_data or 'private_key' not in key_data:
        return None, None

    try:
        from cryptography.hazmat.primitives import hashes, serialization
        from cryptography.hazmat.primitives.asymmetric import padding

        header = base64.urlsafe_b64encode(json.dumps({'alg': 'RS256', 'typ': 'JWT'}).encode('utf-8')).decode('utf-8').rstrip('=')
        claims = {
            'iss': key_data['client_email'],
            'scope': 'https://www.googleapis.com/auth/firebase.messaging',
            'aud': 'https://oauth2.googleapis.com/token',
            'exp': now + 3600,
            'iat': now,
        }
        payload = base64.urlsafe_b64encode(json.dumps(claims).encode('utf-8')).decode('utf-8').rstrip('=')
        sig_input = f'{header}.{payload}'.encode('utf-8')

        private_key = serialization.load_pem_private_key(key_data['private_key'].encode('utf-8'), password=None)
        sig = private_key.sign(sig_input, padding.PKCS1v15(), hashes.SHA256())
        sig_b64 = base64.urlsafe_b64encode(sig).decode('utf-8').rstrip('=')
        jwt_token = f'{header}.{payload}.{sig_b64}'

        token_req = urllib.request.Request(
            'https://oauth2.googleapis.com/token',
            data=urllib.parse.urlencode({
                'grant_type': 'urn:ietf:params:oauth:grant-type:jwt-bearer',
                'assertion': jwt_token,
            }).encode('utf-8'),
            headers={'Content-Type': 'application/x-www-form-urlencoded'}
        )
        with urllib.request.urlopen(token_req, timeout=10) as resp:
            data = json.loads(resp.read().decode('utf-8'))
            access_token = data.get('access_token')
            expires_in = data.get('expires_in', 3600)
            project_id = key_data.get('project_id', 'aixolo')
            _FCM_TOKEN_CACHE = (access_token, now + int(expires_in), project_id)
            return access_token, project_id
    except Exception as e:
        _logger.warning("Failed to obtain FCM access token: %s", e)
        return None, None


class FfNotification(models.Model):
    _name = 'ff.notification'
    _description = 'Field App Notification'
    _order = 'create_date desc, id desc'

    employee_id = fields.Many2one('hr.employee', required=True, index=True, ondelete='cascade')
    user_id = fields.Many2one('res.users', string='Odoo User', index=True, ondelete='cascade')
    title = fields.Char(required=True)
    body = fields.Text()
    kind = fields.Selection(KINDS, default='info', required=True, index=True)
    res_model = fields.Char()
    res_id = fields.Integer()
    read_at = fields.Datetime(index=True)
    company_id = fields.Many2one(related='employee_id.company_id', store=True)

    def _send_fcm_push(self):
        """Send push notification to all active devices of the employee."""
        self.ensure_one()
        if not self.employee_id:
            return
        devices = self.env['ff.device'].sudo().search([
            ('employee_id', '=', self.employee_id.id),
            ('active', '=', True),
            ('fcm_token', '!=', False),
        ])
        if not devices:
            return

        access_token, project_id = _get_fcm_access_token(self.env)
        if not access_token or not project_id:
            return

        fcm_url = f'https://fcm.googleapis.com/v1/projects/{project_id}/messages:send'
        headers = {
            'Authorization': f'Bearer {access_token}',
            'Content-Type': 'application/json; UTF-8',
        }

        for device in devices:
            token = device.fcm_token
            if not token:
                continue
            message = {
                'message': {
                    'token': token,
                    'notification': {
                        'title': self.title,
                        'body': self.body or '',
                    },
                    'data': {
                        'id': str(self.id),
                        'title': str(self.title or ''),
                        'body': str(self.body or ''),
                        'model': str(self.res_model or ''),
                        'res_id': str(self.res_id or ''),
                        'kind': str(self.kind or 'info'),
                    },
                    'android': {
                        'priority': 'high',
                        'notification': {
                            'channel_id': 'field_force_notifications',
                            'sound': 'default',
                            'default_sound': True,
                            'default_vibrate_timings': True,
                            'click_action': 'FLUTTER_NOTIFICATION_CLICK',
                        },
                    },
                }
            }
            try:
                req = urllib.request.Request(
                    fcm_url,
                    data=json.dumps(message).encode('utf-8'),
                    headers=headers,
                    method='POST',
                )
                with urllib.request.urlopen(req, timeout=10) as resp:
                    if resp.status == 200:
                        _logger.info("FCM push sent successfully to employee %s (device %s)", self.employee_id.name, device.device_uid)
            except urllib.error.HTTPError as e:
                err_body = e.read().decode('utf-8', errors='ignore')
                _logger.warning("FCM push HTTP error %s for employee %s: %s", e.code, self.employee_id.name, err_body)
                if e.code in (404, 400) and ('UNREGISTERED' in err_body or 'not a valid FCM registration token' in err_body):
                    device.sudo().write({'fcm_token': False})
            except Exception as e:
                _logger.warning("Failed to send FCM push to employee %s: %s", self.employee_id.name, e)

    @api.model
    def ff_push(self, title, body, kind='info', employee=None, user=None, record=None):
        """Write one notification for whoever this concerns and push to mobile device.

        Either an employee or a user is enough: the other is filled in from it,
        because an approver is an Odoo user who may also be an employee, and a
        claimant is an employee who may not have a login at all.
        """
        if user and not employee:
            employee = user.sudo().employee_id
            if not employee and 'hr.employee' in self.env:
                employee = self.env['hr.employee'].sudo().search([('user_id', '=', user.id)], limit=1)
        if employee and not user:
            user = employee.sudo().user_id
        if not employee:
            return self.browse()  # nobody in the app to tell
        notif = self.sudo().create({
            'employee_id': employee.id,
            'user_id': user.id if user else False,
            'title': title,
            'body': body,
            'kind': kind,
            'res_model': record._name if record else False,
            'res_id': record.id if record else False,
        })
        try:
            notif._send_fcm_push()
        except Exception as e:
            _logger.warning("Error triggering FCM push in ff_push: %s", e)
        return notif

    @api.model
    def ff_for(self, employee, unread_only=False, limit=50):
        domain = [('employee_id', '=', employee.id)]
        if unread_only:
            domain.append(('read_at', '=', False))
        rows = self.sudo().search(domain, limit=limit * 2)
        return rows.filtered(lambda row: not row._ff_about_own_task())[:limit]

    def _ff_about_own_task(self):
        """A notice about a task the person gave themselves: not shown in the bell."""
        self.ensure_one()
        if self.res_model != 'ff.task' or not self.res_id or 'ff.task' not in self.env:
            return False
        task = self.env['ff.task'].sudo().browse(self.res_id).exists()
        return bool(task) and hasattr(task, '_ff_self_assigned') and task._ff_self_assigned()

    def ff_mark_read(self):
        self.sudo().filtered(lambda row: not row.read_at).write({'read_at': fields.Datetime.now()})
        return True

    def ff_payload(self):
        self.ensure_one()
        return {
            'id': self.id,
            'title': self.title,
            'body': self.body or '',
            'kind': self.kind,
            'at': fields.Datetime.to_string(self.create_date),
            'read': bool(self.read_at),
            'model': self.res_model or None,
            'res_id': self.res_id or None,
        }

    @api.autovacuum
    def _gc_notifications(self):
        """A notification read two months ago is of no use to anybody."""
        limit = fields.Datetime.now() - timedelta(days=60)
        self.sudo().search([('read_at', '<', limit)]).unlink()
