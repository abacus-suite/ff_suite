"""Shared plumbing for the /api/v1 endpoints.

Every response is JSON: ``{"ok": true, "data": ...}`` or
``{"ok": false, "error": {"code": ..., "message": ...}}``.

Authentication uses the employee's own app login (not an Odoo user):
``POST /api/v1/auth/login`` returns a session token, sent afterwards as
``Authorization: Bearer <token>``. What an employee may see is decided by
the "Data Access" scope on their employee record.
"""
import functools
import hashlib
import logging

from odoo import http
from odoo.exceptions import AccessDenied, AccessError, UserError, ValidationError
from odoo.http import request

from odoo.addons.ff_base.tools import (get_settings, google_maps_key, map_provider, map_style, to_iso,
                                       client_time, clock_skew_minutes)

_logger = logging.getLogger(__name__)


class ApiError(Exception):
    def __init__(self, message, status=400, code='bad_request'):
        super().__init__(message)
        self.message = message
        self.status = status
        self.code = code


def action_time(data):
    """The moment of the action (see ff_base.tools.client_time), as an API error when too old."""
    try:
        return client_time(data)[0]
    except ValueError as error:
        raise ApiError(str(error), 422, 'too_old')


def check_device_clock(employee, data, action):
    """Refuse ``action`` from a phone whose clock was moved - unless it is queued offline work."""
    if not data or data.get('at'):
        return
    skew = clock_skew_minutes(data)
    allowed = get_settings(request.env)['max_clock_skew'] or 0
    if skew is None or not allowed or skew <= allowed:
        return
    request.env['ff.compliance.log'].sudo().ff_log(employee, [{
        'type': 'time_tampered', 'detail': 'Phone clock %d min off at %s' % (round(skew), action)}])
    request.env.cr.commit()  # keep the log even though the action is refused
    raise ApiError("Your phone's date or time is wrong by %d minutes. Set it to automatic and try again." % round(skew),
                   409, 'clock_skew')


def require_punched_in(employee, action, data=None):
    """Field work happens on the clock: refuse ``action`` outside a punch-in.

    For work queued offline the question is whether they were punched in *then*.
    Skipped when the employee's app profile has attendance switched off.
    """
    app = request.env['ff.app.profile'].ff_for_employee(employee).ff_payload()
    if not app['features'].get('attendance', True):
        return
    if data and data.get('at'):
        at = action_time(data)
        covering = request.env['hr.attendance'].sudo().search_count([
            ('employee_id', '=', employee.id), ('check_in', '<=', at),
            '|', ('check_out', '=', False), ('check_out', '>=', at)])
        if covering:
            return
    elif employee._ff_open_attendance():
        return
    raise ApiError('Check in for the day (attendance) before you %s.' % action, 409, 'not_punched_in')


def scope_members(employee, member=None):
    """Whose data a screen shows: 'me' (default), 'team' (me and everyone my Data Access covers),
    or one employee id inside that scope. Returns (employees, label)."""
    if member in (None, '', 'me'):
        return employee, employee.name
    team = employee._ff_subordinates()
    if member == 'team':
        return employee | team, '%s and team' % employee.name
    try:
        target = request.env['hr.employee'].sudo().browse(int(member)).exists()
    except (TypeError, ValueError):
        target = None
    if not target or (target != employee and target not in team):
        raise ApiError('Employee not found in your team.', 404, 'not_found')
    return target, target.name


def body():
    data = request.httprequest.get_json(force=True, silent=True)
    return data if isinstance(data, dict) else {}


def _request_uuid():
    uuid = body().get('uuid')
    return uuid if isinstance(uuid, str) and 8 <= len(uuid) <= 64 else None


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
                uuid = _request_uuid() if not public and request.httprequest.method == 'POST' else None
                if uuid:
                    # Sent before (queued offline, or an answer lost on the way): same answer again.
                    seen = request.env['ff.api.receipt'].ff_find(uuid)
                    if seen:
                        return request.make_response(seen.response, status=seen.status, headers=[
                            ('Content-Type', 'application/json; charset=utf-8'), ('X-Replayed', '1')])
                response = func(self, *args, **kwargs)
                if uuid and 200 <= response.status_code < 300:
                    request.env['ff.api.receipt'].ff_store(
                        uuid, kwargs.get('employee'), request.httprequest.path,
                        response.status_code, response.get_data(as_text=True))
                return response
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
            'photo_version': hashlib.sha1(employee.sudo().image_128).hexdigest()[:12] if employee.sudo().image_128 else None,
            'email': employee.work_email or None,
            'team': ref(employee.ff_team_id),
            'designation': ref(employee.ff_designation_id),
            'manager': ref(employee.parent_id),
            'tracking_enabled': employee.ff_tracking_enabled and app['features']['tracking'],
            'timezone': employee.tz or 'UTC',
            'route_label': employee._ff_route_label(),
            'routes': [ref(route) for route in employee.ff_route_ids.sorted('name')],
            'routes_per_day': employee.ff_routes_per_day,
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
            'visit_lock': settings['visit_lock'],
            'visit_steps': settings['visit_steps'],
            'stock_count': settings['stock_count'],
            'visit_recommendations': settings['visit_recommendations'],
            'payment_collection': settings['payment_collection'],
            'idle_logout_hours': settings['idle_logout_hours'],
            'max_clock_skew': settings['max_clock_skew'],
            'map_provider': _app_map_provider(),
            'map_style': map_style(request.env),
            # The key only travels when Google is the chosen provider.
            'google_maps_key': google_maps_key(request.env) if _app_map_provider() == 'google' else '',
            'order_flow': request.env['ir.config_parameter'].sudo().get_param('ff_base.order_flow') or 'direct',
        },
    }


def _app_map_provider():
    """Google for the app's maps only while this month's free tiles last (when the guard is on)."""
    provider = map_provider(request.env)
    if provider == 'google' and 'ff.map.usage' in request.env \
            and not request.env['ff.map.usage'].sudo().ff_google_allowed('tiles'):
        return 'open'
    return provider


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
