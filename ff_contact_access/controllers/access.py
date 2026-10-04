"""Asking for contacts outside one's list, and deciding such requests."""
from odoo import fields, http
from odoo.exceptions import ValidationError
from odoo.http import request

from odoo.addons.ff_mobile_api.controllers.common import ApiError, api_route, body, ok, ref


def request_data(rec):
    return {
        'id': rec.id,
        'employee': ref(rec.employee_id),
        'scope_type': rec.scope_type,
        'target': rec.target,
        'date_from': rec.date_from.isoformat() if rec.date_from else None,
        'date_to': rec.date_to.isoformat() if rec.date_to else None,
        'reason': rec.reason or None,
        'status': rec.status,
        'decision_note': rec.decision_note or None,
        'decided_by': ref(rec.decided_by_id),
    }


class FieldForceContactAccessApi(http.Controller):

    @api_route('/api/v1/contact-access', methods=('GET',))
    def listing(self, employee, **kw):
        Request = request.env['ff.contact.access.request'].sudo()
        team = employee._ff_subordinates()
        waiting = Request.search([('employee_id', 'in', team.ids), ('state', '=', 'pending')]) if team else Request
        mine = Request.search([('employee_id', '=', employee.id)], limit=50)
        return ok({
            'mine': [request_data(r) for r in mine],
            'to_decide': [request_data(r) for r in waiting],
            'can_decide': bool(team),
        })

    @api_route('/api/v1/contact-access/options', methods=('GET',))
    def options(self, employee, **kw):
        env = request.env
        return ok({
            'territories': [ref(t) for t in env['ff.territory'].sudo().search([])],
            'cities': [ref(d) for d in env['ff.district'].sudo().search([])],
            'beats': [dict(ref(b), territory=ref(b.territory_id), city=ref(b.district_id))
                      for b in env['ff.beat'].sudo().search([])],
        })

    @api_route('/api/v1/contact-access', methods=('POST',))
    def create(self, employee, **kw):
        data = body()
        scope = data.get('scope_type')
        if scope not in ('territory', 'beat', 'city'):
            raise ApiError('Choose territory, beat or city.', 400, 'bad_request')
        try:
            date_from = fields.Date.to_date(data.get('date_from')) or fields.Date.context_today(employee)
            date_to = fields.Date.to_date(data.get('date_to'))
        except (TypeError, ValueError):
            raise ApiError('Give the dates as YYYY-MM-DD.', 400, 'bad_request')
        if not date_to:
            raise ApiError('Say until when you need it.', 400, 'bad_request')
        vals = {'employee_id': employee.id, 'scope_type': scope, 'date_from': date_from, 'date_to': date_to,
                'reason': (data.get('reason') or '').strip() or False}
        vals[{'territory': 'territory_id', 'beat': 'beat_id', 'city': 'district_id'}[scope]] = \
            int(data.get('target_id') or 0) or False
        try:
            rec = request.env['ff.contact.access.request'].sudo().create(vals)
        except ValidationError as error:
            raise ApiError(str(error), 400, 'invalid')
        return ok(request_data(rec), status=201)

    @api_route('/api/v1/contact-access/<int:rid>/decide', methods=('POST',))
    def decide(self, employee, rid, **kw):
        rec = request.env['ff.contact.access.request'].sudo().browse(rid).exists()
        if not rec:
            raise ApiError('Request not found.', 404, 'not_found')
        data = body()
        try:
            rec.ff_decide(employee, bool(data.get('approve')), (data.get('note') or '').strip() or None)
        except ValidationError as error:
            raise ApiError(str(error), 403, 'forbidden')
        return ok(request_data(rec))
