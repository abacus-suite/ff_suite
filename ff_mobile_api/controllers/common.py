"""Shared plumbing for the /api/v1 endpoints.

Every response is JSON: ``{"ok": true, "data": ...}`` or
``{"ok": false, "error": {"code": ..., "message": ...}}``.

Authentication uses the employee's own app login (not an Odoo user):
``POST /api/v1/auth/login`` returns a session token, sent afterwards as
``Authorization: Bearer <token>``. What an employee may see is decided by
the "Data Access" scope on their employee record.
"""
import functools
import logging

from odoo import http
from odoo.exceptions import AccessDenied, AccessError, UserError, ValidationError
from odoo.http import request

from odoo.addons.ff_base.tools import get_settings, to_iso

_logger = logging.getLogger(__name__)


class ApiError(Exception):
    def __init__(self, message, status=400, code='bad_request'):
        super().__init__(message)
        self.message = message
        self.status = status
        self.code = code


def body():
    data = request.httprequest.get_json(force=True, silent=True)
    return data if isinstance(data, dict) else {}


def ok(data=None, status=200):
    return request.make_json_response({'ok': True, 'data': data}, status=status)


def fail(code, message, status):
    return request.make_json_response({'ok': False, 'error': {'code': code, 'message': message}}, status=status)


def bearer_token():
    header = request.httprequest.headers.get('Authorization', '')
    return header[7:].strip() if header[:7].lower() == 'bearer ' else None


def current_employee(manager=False):
    token = request.env['ff.app.token'].sudo().ff_resolve(bearer_token())
    if not token:
        raise ApiError('Your session has expired. Please log in again.', 401, 'unauthorized')
    employee = token.employee_id.sudo()
    if manager and employee.ff_access_scope == 'own':
        raise ApiError('Manager access required.', 403, 'forbidden')
    return employee


def api_route(route, methods=('GET',), public=False, manager=False):
    """Declare a JSON API route; authenticated routes get an ``employee`` kwarg."""
    def decorator(func):
        @http.route(route, type='http', auth='public', methods=list(methods), csrf=False, save_session=False)
        @functools.wraps(func)
        def wrapper(self, *args, **kwargs):
            try:
                if not public:
                    kwargs['employee'] = current_employee(manager=manager)
                return func(self, *args, **kwargs)
            except ApiError as e:
                request.env.cr.rollback()
                return fail(e.code, e.message, e.status)
            except AccessDenied:
                request.env.cr.rollback()
                return fail('unauthorized', 'Invalid credentials.', 401)
            except AccessError as e:
                request.env.cr.rollback()
                return fail('forbidden', str(e.args[0] if e.args else e), 403)
            except (UserError, ValidationError) as e:
                request.env.cr.rollback()
                return fail('validation_error', str(e.args[0] if e.args else e), 400)
            except Exception:
                request.env.cr.rollback()
                _logger.exception('Field Force API error on %s', route)
                return fail('server_error', 'Unexpected server error.', 500)
        return wrapper
    return decorator


def ref(record):
    return {'id': record.id, 'name': record.display_name} if record else None


def employee_profile(employee):
    settings = get_settings(request.env)
    shift = employee.ff_shift_id
    scope = employee.ff_access_scope
    app = request.env['ff.app.profile'].ff_for_employee(employee).ff_payload()
    return {
        'app': app,
        'employee': {
            'id': employee.id,
            'name': employee.name,
            'code': employee.ff_employee_code or None,
            'job_title': employee.job_title or None,
            'phone': employee.mobile_phone or employee.work_phone or None,
            'email': employee.work_email or None,
            'team': ref(employee.ff_team_id),
            'designation': ref(employee.ff_designation_id),
            'manager': ref(employee.parent_id),
            'tracking_enabled': employee.ff_tracking_enabled and app['features']['tracking'],
            'timezone': employee.tz or 'UTC',
            'route_label': employee._ff_route_label(),
        },
        'roles': {
            'scope': scope,
            'is_manager': scope != 'own',
            'is_admin': scope == 'all',
        },
        'shift': {
            'id': shift.id,
            'name': shift.name,
            'start_time': shift.start_time,
            'end_time': shift.end_time,
            'grace_minutes': shift.grace_minutes,
        } if shift else None,
        'settings': {
            'ping_interval': settings['ping_interval'],
            'distance_filter': settings['distance_filter'],
            'idle_threshold': settings['idle_threshold'],
            'low_battery': settings['low_battery'],
            'selfie_required': settings['selfie_required'],
            'allow_mock': settings['allow_mock'],
        },
    }


def attendance_data(att):
    if not att:
        return None
    return {
        'id': att.id,
        'check_in': to_iso(att.check_in),
        'check_out': to_iso(att.check_out),
        'worked_hours': round(att.worked_hours or 0.0, 2),
        'status': att.ff_day_status,
        'late_minutes': att.ff_late_minutes,
        'in_address': att.ff_in_address or None,
        'out_address': att.ff_out_address or None,
        'source': att.ff_source,
    }


def regularisation_data(rec):
    return {
        'id': rec.id,
        'employee': ref(rec.employee_id),
        'date': rec.date.isoformat(),
        'check_in': to_iso(rec.check_in),
        'check_out': to_iso(rec.check_out),
        'reason': rec.reason,
        'note': rec.note or None,
        'state': rec.state,
        'approver': ref(rec.approver_id),
        'decided_at': to_iso(rec.decided_at),
    }
