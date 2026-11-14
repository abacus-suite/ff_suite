"""Expense endpoints for the Field Force app."""
import calendar
from datetime import date as date_type

from odoo import fields, http
from odoo.exceptions import AccessError, UserError
from odoo.http import request

from odoo.addons.ff_base.tools import to_iso
from odoo.addons.ff_mobile_api.controllers.clients import to_int
from odoo.addons.ff_mobile_api.controllers.common import ApiError, api_route, body, note_rejection, ok, ref


STATE_LABELS = {
    'draft': 'Not sent', 'submitted': 'Sent for approval', 'approved': 'Approved',
    'partial': 'Partly approved', 'rejected': 'Rejected', 'recorded': 'Recorded',
}


def claim_data(claim, employee=None):
    blocker = claim.ff_blocker(employee) if employee and claim.state == 'draft' else ''
    return {
        'id': claim.id,
        'employee': ref(claim.employee_id),
        'kind': claim.kind,
        'date': claim.date.isoformat(),
        'category': ref(claim.category_id),
        'sub_category': ref(claim.sub_category_id),
        'payment_mode': ref(claim.payment_mode_id),
        'amount': claim.amount,
        'approved_amount': claim.approved_amount if claim.state in ('approved', 'partial', 'rejected') else None,
        'currency': claim.currency_id.name,
        'note': claim.note or None,
        'contact': ref(claim.partner_id),
        'visit_id': claim.visit_id.id or None,
        'receipt_count': claim.receipt_count,
        'reference': claim.ff_reference or None,
        'state': claim.state,
        'state_label': STATE_LABELS.get(claim.state, claim.state),
        'reason': claim.decision_reason or None,
        'approver': ref(claim.approver_id),
        'decided_at': to_iso(claim.decided_at),
        'send_deadline': to_iso(claim.send_deadline),
        'can_send': claim.state == 'draft' and claim.kind == 'claim' and not blocker,
        'send_blocker': blocker or None,
        'editable': claim.state == 'draft' and claim.kind == 'claim',
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
        """Categories with their sub-categories, and the company cards."""
        categories = request.env['ff.expense.category'].ff_for_employee(employee).sorted(lambda c: (c.name or '').lower())
        return ok({
            'categories': [{
                'id': c.id,
                'name': c.name,
                'requires_receipt': c.requires_receipt,
                'requires_client': c.requires_client,
                'max_amount': c.max_amount or None,
                'currency': c.currency_id.name,
                'children': [ref(child) for child in c.child_ids.sorted(lambda c: (c.name or '').lower())],
            } for c in categories],
            'cards': [ref(card) for card in request.env['ff.expense.card'].sudo().search([
                ('company_id', 'in', employee.company_id.ids),
                '|', ('employee_ids', '=', False), ('employee_ids', 'in', employee.id),
            ], order='name')],
        })

    @api_route('/api/v1/expenses', methods=('GET',))
    def expenses(self, employee, month=None, kind=None, **kw):
        first, last = month_bounds(employee, month)
        kind = 'card' if kind == 'card' else 'claim'
        claims = request.env['ff.expense.claim'].sudo().search([
            ('employee_id', '=', employee.id), ('kind', '=', kind),
            ('date', '>=', first), ('date', '<=', last),
        ])
        current_first = employee._ff_today().replace(day=1)
        if first == current_first:
            # Everything not yet sent from older periods, so nothing is forgotten in the current month view.
            unsent = request.env['ff.expense.claim'].sudo().search([
                ('employee_id', '=', employee.id), ('kind', '=', kind), ('state', '=', 'draft'),
                ('date', '<', first), ('id', 'not in', claims.ids)])
            every = claims | unsent
        else:
            # When viewing a specific month (previous or future), show only that month's claims.
            every = claims
        counted = every.filtered(lambda c: c.state != 'rejected')
        return ok({
            'month': first.strftime('%Y-%m'),
            'total_amount': round(sum(counted.mapped('amount')), 2),
            'approved_amount': round(sum(c.approved_amount for c in every if c.state in ('approved', 'partial')), 2),
            'currency': every[:1].currency_id.name or employee.company_id.currency_id.name,
            'claims': [claim_data(c, employee) for c in every.sorted(lambda c: (c.date, c.id), reverse=True)],
        })

    @api_route('/api/v1/expenses/summary', methods=('GET',))
    def summary(self, employee, month=None, **kw):
        """What the month holds in every category - travel and daily allowance, OLA, expense claims, company card
        expenses and payment requests - with what was claimed and what was approved, and the totals of all of them."""
        env = request.env
        first, last = month_bounds(employee, month)
        in_month = [('employee_id', '=', employee.id), ('date', '>=', first), ('date', '<=', last)]
        out = {}

        def put(key, claimed, approved, count):
            out[key] = {'claimed': round(claimed, 2), 'approved': round(approved, 2), 'count': count}

        claims = env['ff.expense.claim'].sudo().search(in_month + [('kind', '=', 'claim')])
        counted = claims.filtered(lambda c: c.state != 'rejected')
        put('claim', sum(counted.mapped('amount')),
            sum(c.approved_amount for c in claims if c.state in ('approved', 'partial')), len(claims))
        cards = env['ff.expense.claim'].sudo().search(in_month + [('kind', '=', 'card')])
        put('card', sum(cards.filtered(lambda c: c.state != 'rejected').mapped('amount')), 0.0, len(cards))
        if 'ff.allowance.claim' in env:
            rows = env['ff.allowance.claim'].sudo().search(in_month)
            put('ta', sum(r.amount for r in rows if r.state != 'rejected'),
                sum(r.amount for r in rows if r.state == 'approved'), len(rows))
        if 'ff.da.claim' in env:
            rows = env['ff.da.claim'].sudo().search(in_month)
            put('da', sum(r.amount for r in rows if r.state in ('submitted', 'approved')),
                sum(r.amount for r in rows if r.state == 'approved'), len(rows))
        if 'ff.ola.claim' in env:
            # OLA is paid by the hours worked: there is no approval step to wait for.
            rows = env['ff.ola.claim'].sudo().search(in_month)
            put('ola', sum(rows.mapped('amount')), sum(rows.mapped('amount')), len(rows))
        requests = env['ff.expense.request'].sudo().search(in_month)
        put('request', sum(r.amount for r in requests if r.state != 'rejected'),
            sum(r.amount for r in requests if r.state in ('invoice_pending', 'completed')), len(requests))
        # The company card is the company's own spending: it is shown, but not added to what is claimed.
        summed = [v for k, v in out.items() if k != 'card']
        return ok({
            'month': first.strftime('%Y-%m'),
            'currency': employee.company_id.currency_id.name,
            'total_amount': round(sum(v['claimed'] for v in summed), 2),
            'approved_amount': round(sum(v['approved'] for v in summed), 2),
            'categories': out,
        })

    @api_route('/api/v1/expenses', methods=('POST',))
    def create_expense(self, employee, **kw):
        try:
            claim = request.env['ff.expense.claim'].sudo().ff_create_from_app(employee, body())
        except UserError as error:
            raise ApiError(str(error), 400, 'invalid')
        return ok(claim_data(claim, employee), status=201)

    @api_route('/api/v1/expenses/<int:claim_id>', methods=('GET',))
    def expense(self, employee, claim_id, **kw):
        claim = _mine(employee, claim_id)
        return ok(claim_data(claim, employee))

    @api_route('/api/v1/expenses/<int:claim_id>/update', methods=('POST',))
    def update_expense(self, employee, claim_id, **kw):
        claim = _mine(employee, claim_id)
        try:
            claim.ff_update_from_app(employee, body())
        except (UserError, AccessError) as error:
            raise ApiError(str(error), 400, 'invalid')
        return ok(claim_data(claim, employee))

    @api_route('/api/v1/expenses/send', methods=('POST',))
    def send_expenses(self, employee, **kw):
        """Send the ticked expenses for approval."""
        ids = [to_int(value) for value in (body().get('ids') or [])]
        claims = request.env['ff.expense.claim'].sudo().browse([i for i in ids if i]).exists()
        if not claims:
            raise ApiError('Choose the expenses to send.', 400, 'invalid')
        try:
            request.env['ff.expense.claim'].sudo().ff_send_from_app(employee, claims)
        except (UserError, AccessError) as error:
            request.env.cr.rollback()
            raise ApiError(str(error), 400, 'invalid')
        return ok([claim_data(c, employee) for c in claims])

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
        data = body()
        amount = data.get('amount')
        try:
            claim._ff_decide_as(employee, decision == 'approve',
                                amount=float(amount) if amount not in (None, '') else None,
                                reason=data.get('reason'))
        except (UserError, AccessError, ValueError) as error:
            request.env.cr.rollback()
            raise ApiError(str(error), 400, 'invalid')
        note_rejection(claim, decision == 'approve', employee)
        return ok(claim_data(claim))


def _mine(employee, claim_id):
    claim = request.env['ff.expense.claim'].sudo().browse(claim_id).exists()
    if not claim or claim.employee_id != employee:
        raise ApiError('Expense not found.', 404, 'not_found')
    return claim
