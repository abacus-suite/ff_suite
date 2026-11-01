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
        'source': rec.source,
    }


class FieldForceContactAccessApi(http.Controller):

    @api_route('/api/v1/contact-access', methods=('GET',))
    def listing(self, employee, **kw):
        Request = request.env['ff.contact.access.request'].sudo()
        team = employee._ff_subordinates()
        waiting = Request.search([('employee_id', 'in', team.ids), ('state', '=', 'pending')]) if team else Request
        mine = Request.search([('employee_id', '=', employee.id)], limit=50)
        # What the manager has given the team lately, by request or by hand.
        given = Request.search([('employee_id', 'in', team.ids), ('state', '!=', 'pending')], limit=40) if team else Request
        return ok({
            'mine': [request_data(r) for r in mine],
            'given': [request_data(r) for r in given],
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

    @api_route('/api/v1/contact-access/assign', methods=('POST',))
    def assign(self, employee, **kw):
        """A manager gives somebody in their team access directly, for a day or a stretch.

        Approved at once. With ``plan_day`` and a beat, that beat is also planned for the person on the
        first day, so their check-in finds it ready.
        """
        data = body()
        target = request.env['hr.employee'].sudo().browse(int(data.get('employee_id') or 0)).exists()
        if not target or target not in employee._ff_subordinates():
            raise ApiError('Choose somebody in your team.', 403, 'forbidden')
        scope = data.get('scope_type')
        if scope not in ('territory', 'beat', 'city'):
            raise ApiError('Choose territory, beat or city.', 400, 'bad_request')
        try:
            date_from = fields.Date.to_date(data.get('date_from')) or fields.Date.context_today(employee)
            date_to = fields.Date.to_date(data.get('date_to')) or date_from
        except (TypeError, ValueError):
            raise ApiError('Give the dates as YYYY-MM-DD.', 400, 'bad_request')
        vals = {'employee_id': target.id, 'scope_type': scope, 'date_from': date_from, 'date_to': date_to,
                'reason': (data.get('reason') or '').strip() or False}
        vals[{'territory': 'territory_id', 'beat': 'beat_id', 'city': 'district_id'}[scope]] = \
            int(data.get('target_id') or 0) or False
        Request = request.env['ff.contact.access.request'].sudo().with_context(ff_assign=True, ff_assigner=employee.id)
        try:
            rec = Request.create(vals)
            rec.write({'decided_by_id': employee.id})
            planned = False
            if data.get('plan_day') and scope == 'beat' and rec.beat_id:
                Plan = request.env['ff.beat.plan'].sudo().with_context(ff_manager_plan=True)
                Plan.ff_plan_from_app(target, {
                    'beat_id': rec.beat_id.id, 'date': date_from,
                    'partner_ids': rec.beat_id.line_ids.mapped('partner_id').ids})
                planned = True
        except ValidationError as error:
            raise ApiError(str(error), 400, 'invalid')
        return ok(dict(request_data(rec), planned=planned), status=201)

    @api_route('/api/v1/contact-access/<int:rid>/decide', methods=('POST',))
    def decide(self, employee, rid, **kw):
        rec = request.env['ff.contact.access.request'].sudo().browse(rid).exists()
        if not rec:
            raise ApiError('Request not found.', 404, 'not_found')
        data = body()
        try:
            rec.ff_decide(employee, bool(data.get('approve')),
                          (data.get('note') or data.get('reason') or '').strip() or None)
        except ValidationError as error:
            raise ApiError(str(error), 403, 'forbidden')
        return ok(request_data(rec))
