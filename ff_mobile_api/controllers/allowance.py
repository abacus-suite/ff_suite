"""Travel allowance endpoints: own claims, submission and manager approval."""
import calendar
from datetime import date as date_type

from odoo import fields, http
from odoo.http import request

from odoo.addons.ff_base.tools import to_iso

from .common import ApiError, api_route, ok, ref


def claim_data(claim, with_legs=False):
    data = {
        'id': claim.id,
        'employee': ref(claim.employee_id),
        'date': claim.date.isoformat(),
        'basis': claim.basis,
        'distance_km': claim.distance_km,
        'rate_per_km': claim.rate_per_km,
        'amount': claim.amount,
        'currency': claim.currency_id.name,
        'reference': claim.ff_reference or None,
        'state': claim.state,
        'estimated': claim.estimated,
        'visit_count': claim.visit_count,
        'policy': ref(claim.policy_id),
    }
    if with_legs:
        data['legs'] = [{
            'name': line.name,
            'km': line.distance_km,
            'estimated': line.estimated,
        } for line in claim.line_ids]
    return data


def _month_bounds(employee, month):
    """First and last day of a YYYY-MM month; the current month when empty."""
    if month:
        try:
            year, number = (int(part) for part in str(month).split('-')[:2])
            first = date_type(year, number, 1)
        except (ValueError, TypeError):
            raise ApiError('month must be YYYY-MM.')
    else:
        first = employee._ff_today().replace(day=1)
    return first, date_type(first.year, first.month, calendar.monthrange(first.year, first.month)[1])


class FieldForceAllowanceApi(http.Controller):

    @api_route('/api/v1/allowances', methods=('GET',))
    def allowances(self, employee, month=None, **kw):
        first, last = _month_bounds(employee, month)
        claims = request.env['ff.allowance.claim'].sudo().search([
            ('employee_id', '=', employee.id), ('date', '>=', first), ('date', '<=', last),
        ], order='date desc')
        payable = claims.filtered(lambda c: c.state != 'rejected')
        return ok({
            'month': first.strftime('%Y-%m'),
            'total_km': round(sum(payable.mapped('distance_km')), 2),
            'total_amount': round(sum(payable.mapped('amount')), 2),
            'currency': claims[:1].currency_id.name or employee.company_id.currency_id.name,
            'approved_amount': round(sum(claims.filtered(lambda c: c.state == 'approved').mapped('amount')), 2),
            'claims': [claim_data(c) for c in claims],
        })

    @api_route('/api/v1/allowances/<int:claim_id>', methods=('GET',))
    def allowance(self, employee, claim_id, **kw):
        claim = request.env['ff.allowance.claim'].sudo().browse(claim_id).exists()
        if not claim or (claim.employee_id != employee and claim.employee_id not in employee._ff_subordinates()):
            raise ApiError('Allowance not found.', 404, 'not_found')
        return ok(claim_data(claim, with_legs=True))

    @api_route('/api/v1/allowances/<int:claim_id>/submit', methods=('POST',))
    def submit(self, employee, claim_id, **kw):
        claim = request.env['ff.allowance.claim'].sudo().browse(claim_id).exists()
        if not claim or claim.employee_id != employee:
            raise ApiError('Allowance not found.', 404, 'not_found')
        claim.action_submit()
        return ok(claim_data(claim))

    @api_route('/api/v1/allowances/to-approve', methods=('GET',), manager=True)
    def to_approve(self, employee, **kw):
        Claim = request.env['ff.allowance.claim']
        claims = Claim.sudo().search([
            ('employee_id', 'in', employee._ff_subordinates().ids), ('state', '=', 'submitted'),
        ], order='date desc')
        # An approval flow decides the queue when one is configured.
        if hasattr(Claim, 'ff_waiting_for') and employee.user_id:
            mine = Claim.ff_waiting_for(employee.user_id)
            claims = (claims.filtered(lambda claim: not claim.approval_line_ids) | mine)
        return ok([claim_data(c, with_legs=True) for c in claims])

    @api_route('/api/v1/approvals/allowance/<int:claim_id>/<string:decision>', methods=('POST',), manager=True)
    def decide(self, employee, claim_id, decision, **kw):
        if decision not in ('approve', 'reject'):
            raise ApiError('decision must be "approve" or "reject".')
        claim = request.env['ff.allowance.claim'].sudo().browse(claim_id).exists()
        if not claim or claim.employee_id not in employee._ff_subordinates():
            raise ApiError('Allowance not found.', 404, 'not_found')
        claim._ff_decide_as(employee, decision == 'approve')
        return ok(claim_data(claim))

    @api_route('/api/v1/allowances/today', methods=('GET',))
    def today(self, employee, **kw):
        """Draft allowance of the current day, recalculated on the fly."""
        claim = request.env['ff.allowance.claim']._ff_compute(employee, employee._ff_today())
        return ok({
            'server_time': to_iso(fields.Datetime.now()),
            'claim': claim_data(claim, with_legs=True) if claim else None,
        })
