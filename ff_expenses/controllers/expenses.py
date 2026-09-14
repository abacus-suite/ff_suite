"""Expense endpoints for the Field Force app."""
import calendar
from datetime import date as date_type

from odoo import http
from odoo.http import request

from odoo.addons.ff_base.tools import to_iso
from odoo.addons.ff_mobile_api.controllers.common import ApiError, api_route, body, ok, ref


def claim_data(claim):
    return {
        'id': claim.id,
        'employee': ref(claim.employee_id),
        'date': claim.date.isoformat(),
        'category': ref(claim.category_id),
        'amount': claim.amount,
        'currency': claim.currency_id.name,
        'note': claim.note or None,
        'contact': ref(claim.partner_id),
        'visit_id': claim.visit_id.id or None,
        'receipt_count': claim.receipt_count,
        'reference': claim.ff_reference or None,
        'state': claim.state,
        'approver': ref(claim.approver_id),
        'decided_at': to_iso(claim.decided_at),
    }


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


class FieldForceExpensesApi(http.Controller):

    @api_route('/api/v1/expense-categories', methods=('GET',))
    def categories(self, employee, **kw):
        categories = request.env['ff.expense.category'].ff_for_employee(employee)
        return ok([{
            'id': c.id,
            'name': c.name,
            'requires_receipt': c.requires_receipt,
            'requires_client': c.requires_client,
            'max_amount': c.max_amount or None,
            'currency': c.currency_id.name,
        } for c in categories])

    @api_route('/api/v1/expenses', methods=('GET',))
    def expenses(self, employee, month=None, **kw):
        first, last = month_bounds(employee, month)
        claims = request.env['ff.expense.claim'].sudo().search([
            ('employee_id', '=', employee.id), ('date', '>=', first), ('date', '<=', last),
        ])
        approved = claims.filtered(lambda c: c.state == 'approved')
        return ok({
            'month': first.strftime('%Y-%m'),
            'total_amount': round(sum(claims.filtered(lambda c: c.state != 'rejected').mapped('amount')), 2),
            'approved_amount': round(sum(approved.mapped('amount')), 2),
            'currency': claims[:1].currency_id.name or employee.company_id.currency_id.name,
            'claims': [claim_data(c) for c in claims],
        })

    @api_route('/api/v1/expenses', methods=('POST',))
    def create_expense(self, employee, **kw):
        claim = request.env['ff.expense.claim'].ff_create_from_app(employee, body())
        return ok(claim_data(claim), status=201)

    @api_route('/api/v1/expenses/to-approve', methods=('GET',), manager=True)
    def to_approve(self, employee, **kw):
        Claim = request.env['ff.expense.claim']
        claims = Claim.sudo().search([
            ('employee_id', 'in', employee._ff_subordinates().ids), ('state', '=', 'submitted'),
        ])
        # With an approval flow the queue is whatever waits on this person's
        # step, which is not always one of their own subordinates.
        if hasattr(Claim, 'ff_waiting_for') and employee.user_id:
            mine = Claim.ff_waiting_for(employee.user_id)
            claims = (claims.filtered(lambda claim: not claim.approval_line_ids) | mine)
        return ok([claim_data(c) for c in claims])

    @api_route('/api/v1/approvals/expense/<int:claim_id>/<string:decision>', methods=('POST',), manager=True)
    def decide(self, employee, claim_id, decision, **kw):
        if decision not in ('approve', 'reject'):
            raise ApiError('decision must be "approve" or "reject".')
        claim = request.env['ff.expense.claim'].sudo().browse(claim_id).exists()
        if not claim or claim.employee_id not in employee._ff_subordinates():
            raise ApiError('Claim not found.', 404, 'not_found')
        claim._ff_decide_as(employee, decision == 'approve')
        return ok(claim_data(claim))
