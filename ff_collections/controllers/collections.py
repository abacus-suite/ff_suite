"""Payment collection endpoints for the Aixolo app."""
import calendar
from datetime import date as date_type

from odoo import http
from odoo.http import request

from odoo.addons.ff_base.tools import get_param, to_iso
from odoo.addons.ff_mobile_api.controllers.clients import to_int
from odoo.addons.ff_mobile_api.controllers.common import ApiError, action_time, api_route, body, ok, ref, require_punched_in


def collection_data(collection):
    return {
        'id': collection.id,
        'employee': ref(collection.employee_id),
        'contact': ref(collection.partner_id),
        'date': to_iso(collection.date),
        'mode': ref(collection.mode_id),
        'mode_type': collection.mode_type,
        'amount': collection.amount,
        'currency': collection.currency_id.name,
        'reference': collection.reference or None,
        'instrument_date': collection.instrument_date.isoformat() if collection.instrument_date else None,
        'note': collection.note or None,
        'photo_count': collection.photo_count,
        'state': collection.state,
        'deposit_id': collection.deposit_id.id or None,
        'visit_id': collection.visit_id.id or None,
    }


def deposit_data(deposit, with_lines=False):
    data = {
        'id': deposit.id,
        'name': deposit.name,
        'employee': ref(deposit.employee_id),
        'amount': deposit.amount,
        'currency': deposit.currency_id.name,
        'count': deposit.collection_count,
        'state': deposit.state,
        'submitted_at': to_iso(deposit.submitted_at),
        'received_at': to_iso(deposit.received_at),
        'reference': deposit.reference or None,
    }
    if with_lines:
        data['collections'] = [collection_data(c) for c in deposit.collection_ids]
    return data


def month_bounds(employee, month):
    if month:
        try:
            year, number = (int(part) for part in str(month).split('-')[:2])
            first = date_type(year, number, 1)
        except (ValueError, TypeError):
            raise ApiError('month must be YYYY-MM.')
    else:
        first = employee._ff_today().replace(day=1)
    return first, date_type(first.year, first.month, calendar.monthrange(first.year, first.month)[1])


def check_enabled():
    if not get_param(request.env, 'payment_collection'):
        raise ApiError('Payment collection is switched off.', 403, 'forbidden')


class FieldForceCollectionsApi(http.Controller):

    @api_route('/api/v1/collection-modes', methods=('GET',))
    def modes(self, employee, **kw):
        check_enabled()
        modes = request.env['ff.collection.mode'].ff_for_employee(employee)
        return ok([{
            'id': m.id,
            'name': m.name,
            'type': m.mode_type,
            'requires_reference': m.requires_reference,
            'requires_photo': m.requires_photo,
            'requires_instrument_date': m.requires_instrument_date,
            'needs_deposit': m.needs_deposit,
            'max_amount': m.max_amount or None,
            'currency': m.currency_id.name,
        } for m in modes])

    @api_route('/api/v1/collections', methods=('POST',))
    def create_collection(self, employee, **kw):
        check_enabled()
        data = body()
        partner = request.env['res.partner'].sudo().browse(to_int(data.get('partner_id'))).exists()
        if partner:
            require_punched_in(employee, 'collect a payment', data)
            request.env['ff.visit'].ff_require_visit(employee, partner, action_time(data) if data.get('at') else None)
        collection = request.env['ff.collection'].ff_create_from_app(employee, data)
        return ok(collection_data(collection), status=201)

    @api_route('/api/v1/collections', methods=('GET',))
    def collections(self, employee, month=None, **kw):
        check_enabled()
        first, last = month_bounds(employee, month)
        start, _unused = employee._ff_day_bounds(first)
        _unused2, end = employee._ff_day_bounds(last)
        records = request.env['ff.collection'].sudo().search([
            ('employee_id', '=', employee.id), ('date', '>=', start), ('date', '<', end),
        ])
        counted = records.filtered(lambda c: c.state != 'cancelled')
        return ok({
            'month': first.strftime('%Y-%m'),
            'total_amount': round(sum(counted.mapped('amount')), 2),
            'currency': records[:1].currency_id.name or employee.company_id.currency_id.name,
            'pending': request.env['ff.collection'].ff_pending_status(employee),
            'collections': [collection_data(c) for c in records],
        })

    @api_route('/api/v1/collections/pending', methods=('GET',))
    def pending(self, employee, **kw):
        check_enabled()
        Collection = request.env['ff.collection']
        pending = Collection._ff_pending(employee)
        status = Collection.ff_pending_status(employee)
        status['oldest_date'] = to_iso(status['oldest_date']) if status['oldest_date'] else None
        return ok({'status': status, 'collections': [collection_data(c) for c in pending]})

    @api_route('/api/v1/deposits', methods=('POST',))
    def create_deposit(self, employee, **kw):
        check_enabled()
        deposit = request.env['ff.collection.deposit'].ff_submit_from_app(employee, body())
        return ok(deposit_data(deposit, with_lines=True), status=201)

    @api_route('/api/v1/deposits', methods=('GET',))
    def deposits(self, employee, limit=None, **kw):
        check_enabled()
        records = request.env['ff.collection.deposit'].sudo().search(
            [('employee_id', '=', employee.id)], limit=min(to_int(limit) or 30, 100))
        return ok([deposit_data(d) for d in records])

    @api_route('/api/v1/deposits/to-receive', methods=('GET',), manager=True)
    def to_receive(self, employee, **kw):
        check_enabled()
        records = request.env['ff.collection.deposit'].sudo().search([
            ('employee_id', 'in', employee._ff_subordinates().ids), ('state', '=', 'submitted'),
        ])
        return ok([deposit_data(d, with_lines=True) for d in records])

    @api_route('/api/v1/deposits/<int:deposit_id>/<string:decision>', methods=('POST',), manager=True)
    def decide_deposit(self, employee, deposit_id, decision, **kw):
        check_enabled()
        if decision not in ('receive', 'reject'):
            raise ApiError('decision must be "receive" or "reject".')
        deposit = request.env['ff.collection.deposit'].sudo().browse(deposit_id).exists()
        if not deposit or deposit.employee_id not in employee._ff_subordinates():
            raise ApiError('Deposit not found.', 404, 'not_found')
        deposit._ff_decide_as(employee, decision == 'receive')
        return ok(deposit_data(deposit, with_lines=True))
