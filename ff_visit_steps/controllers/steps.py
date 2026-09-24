"""Visit step endpoints for the Field Force app."""
from odoo import http
from odoo.http import request

from odoo.addons.ff_base.tools import get_param, to_iso
from odoo.addons.ff_mobile_api.controllers.clients import to_int, visible_client
from odoo.addons.ff_mobile_api.controllers.common import ApiError, api_route, body, ok, ref


def own_visit(employee, visit_id, uuid=None):
    """The employee's visit by id; id 0 plus the check-in's uuid finds one made offline."""
    Visit = request.env['ff.visit'].sudo()
    visit = Visit.browse(to_int(visit_id) or []).exists()
    if not visit and uuid:
        visit = Visit.search([('client_uuid', '=', uuid), ('employee_id', '=', employee.id)], limit=1)
    if not visit or visit.employee_id != employee:
        raise ApiError('Visit not found.', 404, 'not_found')
    return visit


def step_data(step, record):
    return {
        'id': step.id,
        'name': step.name,
        'type': step.step_type,
        'sequence': step.sequence,
        'mandatory': step.mandatory,
        'allow_skip': step.allow_skip,
        'skip_reason_required': step.skip_reason_required,
        'instruction': step.help_text or None,
        'form_id': step.form_id.id or None,
        'state': record.state if record else 'pending',
        'note': (record.note or None) if record else None,
        'done_at': to_iso(record.done_at) if record else None,
    }


def last_count_data(count):
    if not count:
        return None
    return {
        'id': count.id,
        'date': to_iso(count.date),
        'employee': ref(count.employee_id),
        'lines': [{
            'product_id': line.product_id.id,
            'product': line.product_id.display_name,
            'quantity': line.quantity,
            'uom': line.uom_name,
        } for line in count.line_ids],
    }


class FieldForceStepsApi(http.Controller):

    @api_route('/api/v1/visits/<int:visit_id>/steps', methods=('GET',))
    def steps(self, employee, visit_id, partner_id=None, **kw):
        if not get_param(request.env, 'visit_steps'):
            return ok({'enabled': False, 'steps': []})
        if not visit_id and partner_id:
            # The steps a visit here would have - saved on the phone for an offline check-in.
            partner = visible_client(employee, to_int(partner_id))
            visit, records = None, {}
        else:
            visit = own_visit(employee, visit_id)
            partner = visit.partner_id
            records = {r.step_id.id: r for r in visit.sudo().step_record_ids}
        steps = request.env['ff.visit.step'].ff_for(employee, partner).sorted('sequence')
        return ok({
            'enabled': True,
            'steps': [step_data(step, records.get(step.id)) for step in steps],
            'last_stock_count': last_count_data(request.env['ff.stock.count'].ff_last_for(partner)),
        })

    @api_route('/api/v1/visits/<int:visit_id>/steps/<int:step_id>', methods=('POST',))
    def complete_step(self, employee, visit_id, step_id, **kw):
        visit = own_visit(employee, visit_id, body().get('visit_uuid'))
        step = request.env['ff.visit.step'].sudo().browse(step_id).exists()
        if not step:
            raise ApiError('Step not found.', 404, 'not_found')
        record = request.env['ff.visit.step.record'].ff_complete(employee, visit, step, body())
        return ok(step_data(step, record), status=201)

    @api_route('/api/v1/stock/last', methods=('GET',))
    def last_stock(self, employee, partner_id=None, **kw):
        partner = visible_client(employee, to_int(partner_id))
        return ok(last_count_data(request.env['ff.stock.count'].ff_last_for(partner)))

    @api_route('/api/v1/stock/counts', methods=('POST',))
    def create_count(self, employee, **kw):
        """Stock count outside a step (Stock count feature switched on)."""
        if not get_param(request.env, 'stock_count'):
            raise ApiError('Stock count is switched off.', 403, 'forbidden')
        data = body()
        partner = visible_client(employee, to_int(data.get('partner_id')))
        lines = data.get('lines') or []
        if not lines:
            raise ApiError('Count at least one product.')
        visit = request.env['ff.visit'].sudo().browse(to_int(data.get('visit_id')) or []).exists()
        if not visit and data.get('visit_uuid'):
            visit = request.env['ff.visit'].sudo().search(
                [('client_uuid', '=', data['visit_uuid']), ('employee_id', '=', employee.id)], limit=1)
        if visit and visit.employee_id != employee:
            raise ApiError('Visit not found.', 404, 'not_found')
        count = request.env['ff.stock.count'].ff_record(employee, partner, lines, visit=visit,
                                                        note=data.get('note'))
        return ok({
            'id': count.id,
            'date': to_iso(count.date),
            'items': count.item_count,
            'lines': [{
                'product': line.product_id.display_name,
                'quantity': line.quantity,
                'previous_quantity': line.previous_quantity,
                'previous_date': to_iso(line.previous_date),
                'delta': line.delta,
            } for line in count.line_ids],
        }, status=201)
