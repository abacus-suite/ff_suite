"""Reports for the app: catalogue, rows, and an Excel download link."""
import base64
import hashlib
import hmac
import json
import time as clock

from odoo import fields, http
from odoo.http import request

from odoo.addons.ff_mobile_api.controllers.common import ApiError, api_route, body, ok, ref

LINK_SECONDS = 600


def _scope(employee, member):
    """Whose rows: 'me', 'team' (everyone under me, and me), or one employee id."""
    team = employee._ff_subordinates()
    if member in (None, '', 'me'):
        return employee, employee.name
    if member == 'team':
        return employee | team, '%s and team' % employee.name
    try:
        target = request.env['hr.employee'].sudo().browse(int(member)).exists()
    except (TypeError, ValueError):
        target = None
    if not target or (target != employee and target not in team):
        raise ApiError('Employee not found in your team.', 404, 'not_found')
    return target, target.name


def _dates(employee, start, end):
    today = employee._ff_today()
    try:
        low = fields.Date.to_date(start) if start else today
        high = fields.Date.to_date(end) if end else low
    except ValueError:
        raise ApiError('Dates must be YYYY-MM-DD.')
    if abs((high - low).days) > 366:
        raise ApiError('Choose a period of one year or less.')
    return low, high


def _sign(payload):
    secret = request.env['ir.config_parameter'].sudo().get_param('database.secret').encode()
    body = base64.urlsafe_b64encode(json.dumps(payload, separators=(',', ':')).encode()).decode()
    digest = hmac.new(secret, body.encode(), hashlib.sha256).hexdigest()
    return '%s.%s' % (body, digest)


def _unsign(token):
    secret = request.env['ir.config_parameter'].sudo().get_param('database.secret').encode()
    body, _dot, digest = (token or '').partition('.')
    if not body or not hmac.compare_digest(hmac.new(secret, body.encode(), hashlib.sha256).hexdigest(), digest):
        return None
    try:
        payload = json.loads(base64.urlsafe_b64decode(body.encode()))
    except ValueError:
        return None
    return payload if payload.get('x', 0) >= clock.time() else None


class FieldForceReportsApi(http.Controller):

    @api_route('/api/v1/reports', methods=('GET',))
    def catalogue(self, employee, **kw):
        team = employee._ff_subordinates()
        return ok({
            'reports': request.env['ff.app.report'].ff_catalogue(),
            'can_team': bool(team),
            'members': [dict(ref(member), code=member.ff_employee_code or None)
                        for member in team.sorted('name')],
            'today': employee._ff_today().isoformat(),
        })

    @api_route('/api/v1/reports/<string:key>', methods=('GET',))
    def run(self, employee, key, start=None, end=None, member=None, **kw):
        employees, _who = _scope(employee, member)
        low, high = _dates(employee, start, end)
        data = request.env['ff.app.report'].ff_run(key, employee, employees, low, high)
        if data is None:
            raise ApiError('Unknown report.', 404, 'not_found')
        return ok(data)

    @api_route('/api/v1/reports/<string:key>/export', methods=('POST',))
    def export(self, employee, key, **kw):
        data = body()
        start, end, member = data.get('start'), data.get('end'), data.get('member')
        _scope(employee, member)
        low, high = _dates(employee, start, end)
        token = _sign({'e': employee.id, 'k': key, 's': low.isoformat(), 'n': high.isoformat(),
                       'm': member or 'me', 'x': int(clock.time()) + LINK_SECONDS})
        # A path: the app puts it on the server address it already talks to.
        return ok({'path': '/api/v1/reports/download?t=%s' % token, 'expires_in': LINK_SECONDS})

    @http.route('/api/v1/reports/download', type='http', auth='public', methods=['GET'], csrf=False,
                save_session=False)
    def download(self, t=None, **kw):
        """Opened in the phone's browser, which cannot send the app's token - so the link carries a signed one."""
        payload = _unsign(t)
        if not payload:
            return request.make_response('This download link has expired. Export again from the app.',
                                         headers=[('Content-Type', 'text/plain; charset=utf-8')], status=410)
        employee = request.env['hr.employee'].sudo().browse(payload['e']).exists()
        if not employee:
            return request.not_found()
        try:
            employees, who = _scope(employee, payload['m'])
        except ApiError:
            return request.not_found()
        low, high = fields.Date.to_date(payload['s']), fields.Date.to_date(payload['n'])
        Report = request.env['ff.app.report'].sudo()
        data = Report.ff_run(payload['k'], employee, employees, low, high)
        if data is None:
            return request.not_found()
        content = Report.ff_xlsx(data, who)
        filename = '%s_%s_%s.xlsx' % (data['title'].replace(' ', '_'), low.isoformat(), high.isoformat())
        return request.make_response(content, headers=[
            ('Content-Type', 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'),
            ('Content-Disposition', 'attachment; filename="%s"' % filename),
            ('Content-Length', str(len(content))),
        ])
