from odoo import fields, http
from odoo.http import request

from .clients import to_float, visible_client
from .common import ApiError, api_route, body, ok
from .field_data import client_data, plan_data, visit_data


def _day(employee, value):
    try:
        return fields.Date.to_date(value) if value else employee._ff_today()
    except ValueError:
        raise ApiError('date must be YYYY-MM-DD.')


def _own_visit(employee, visit_id):
    visit = request.env['ff.visit'].sudo().browse(visit_id).exists()
    if not visit or visit.employee_id != employee:
        raise ApiError('Visit not found.', 404, 'not_found')
    return visit


class FieldForceVisitsApi(http.Controller):

    @api_route('/api/v1/visits/check-in', methods=('POST',))
    def check_in(self, employee, **kw):
        data = body()
        try:
            partner_id = int(data.get('partner_id'))
        except (TypeError, ValueError):
            raise ApiError('partner_id is required.')
        partner = visible_client(employee, partner_id)
        visit = request.env['ff.visit'].ff_check_in(employee, partner, data)
        return ok(visit_data(visit))

    @api_route('/api/v1/visits/<int:visit_id>/check-out', methods=('POST',))
    def check_out(self, employee, visit_id, **kw):
        return ok(visit_data(_own_visit(employee, visit_id).ff_check_out(body())))

    @api_route('/api/v1/visits/current', methods=('GET',))
    def current(self, employee, **kw):
        visit = request.env['ff.visit'].sudo().search(
            [('employee_id', '=', employee.id), ('state', '=', 'ongoing')], limit=1)
        return ok(visit_data(visit))

    @api_route('/api/v1/visits', methods=('GET',))
    def visits(self, employee, date=None, **kw):
        start, end = employee._ff_day_bounds(_day(employee, date))
        visits = request.env['ff.visit'].sudo().search([
            ('employee_id', '=', employee.id), ('check_in_at', '>=', start), ('check_in_at', '<', end),
        ])
        return ok([visit_data(v) for v in visits])

    @api_route('/api/v1/beat/today', methods=('GET',))
    def beat_today(self, employee, date=None, lat=None, lng=None, **kw):
        day = _day(employee, date)
        lat, lng = to_float(lat), to_float(lng)
        start, end = employee._ff_day_bounds(day)
        plan = request.env['ff.beat.plan'].sudo().search(
            [('employee_id', '=', employee.id), ('date', '=', day)], limit=1)
        visits = request.env['ff.visit'].sudo().search([
            ('employee_id', '=', employee.id), ('check_in_at', '>=', start), ('check_in_at', '<', end),
        ], order='check_in_at asc')

        planned_partners = plan.beat_id.line_ids.sorted('sequence').partner_id
        rows = []
        for sequence, partner in enumerate(planned_partners, start=1):
            partner_visits = visits.filtered(lambda v, p=partner: v.partner_id == p)
            status = 'pending'
            if partner_visits.filtered(lambda v: v.state == 'ongoing'):
                status = 'ongoing'
            elif partner_visits:
                status = 'done'
            row = client_data(partner, lat, lng)
            row.update(sequence=sequence, visit_status=status,
                       visit=visit_data(partner_visits[-1:]) if partner_visits else None)
            rows.append(row)

        ongoing = visits.filtered(lambda v: v.state == 'ongoing')[:1]
        return ok({
            'date': day.isoformat(),
            'plan': plan_data(plan),
            'clients': rows,
            'adhoc_visits': [visit_data(v) for v in visits if v.partner_id not in planned_partners],
            'ongoing': visit_data(ongoing),
        })
