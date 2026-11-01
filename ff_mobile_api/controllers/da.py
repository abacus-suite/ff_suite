"""Daily allowance (DA): the person's weeks, and the manager's weekly approval."""
import calendar
from datetime import date as date_type, timedelta

from odoo import http
from odoo.http import request

from .common import ApiError, api_route, note_rejection, ok, ref


def _week_rows(claims):
    """Group claims into weeks: total, days, and where the week stands."""
    weeks = {}
    for claim in claims.sorted('date'):
        row = weeks.setdefault(claim.week_start, {
            'week_start': claim.week_start.isoformat(),
            'week_end': (claim.week_start + timedelta(days=6)).isoformat(),
            'total': 0.0, 'outside_days': 0, 'days': [],
        })
        row['total'] += claim.amount
        row['outside_days'] += 1 if claim.kind == 'outside' else 0
        row['days'].append({
            'id': claim.id, 'date': claim.date.isoformat(), 'kind': claim.kind, 'rate': claim.rate,
            'amount': claim.amount, 'visits': claim.visit_count, 'outside_visits': claim.outside_count,
            'state': claim.state, 'detail': claim.detail or '',
        })
    out = []
    for row in sorted(weeks.values(), key=lambda r: r['week_start'], reverse=True):
        states = {d['state'] for d in row['days']}
        row['total'] = round(row['total'], 2)
        row['state'] = ('approved' if states == {'approved'} else 'rejected' if states == {'rejected'}
                        else 'submitted' if 'submitted' in states else 'draft')
        out.append(row)
    return out


class FieldForceDaApi(http.Controller):

    @api_route('/api/v1/da', methods=('GET',))
    def my_da(self, employee, month=None, **kw):
        env = request.env
        today = employee._ff_today()
        if month:
            try:
                year, number = (int(p) for p in str(month).split('-')[:2])
                first = date_type(year, number, 1)
            except (ValueError, TypeError):
                raise ApiError('month must be YYYY-MM.')
        else:
            first = today.replace(day=1)
        last = date_type(first.year, first.month, calendar.monthrange(first.year, first.month)[1])
        Claim = env['ff.da.claim']
        # The last days are worked out on the spot, so today's visits count at once.
        day = max(first, today - timedelta(days=9))
        while day <= min(last, today):
            Claim._ff_compute(employee, day)
            day += timedelta(days=1)
        # The weeks that touch the month.
        claims = Claim.sudo().search([
            ('employee_id', '=', employee.id), ('date', '>=', first - timedelta(days=6)), ('date', '<=', last)])
        claims = claims.filtered(lambda c: c.amount or c.kind != 'none')
        rate = env['ff.da.rate']._ff_for_employee(employee)
        weeks = _week_rows(claims)
        return ok({
            'month': first.strftime('%Y-%m'),
            'currency': employee.company_id.currency_id.name,
            'rates': {
                'designation': employee.ff_designation_id.name or None,
                'primary': None if (not rate or rate.primary_na) else rate.primary_rate,
                'outside': rate.outside_rate if rate else None,
                'set': bool(rate),
            },
            'total': round(sum(claims.filtered(lambda c: first <= c.date <= last and c.state != 'rejected')
                               .mapped('amount')), 2),
            'weeks': weeks,
        })

    @api_route('/api/v1/da/to-approve', methods=('GET',), manager=True)
    def to_approve(self, employee, **kw):
        claims = request.env['ff.da.claim'].sudo().search([
            ('employee_id', 'in', employee._ff_subordinates().ids), ('state', '=', 'submitted')])
        groups = {}
        for claim in claims:
            groups.setdefault((claim.employee_id.id, claim.week_start), request.env['ff.da.claim'])
            groups[(claim.employee_id.id, claim.week_start)] |= claim
        out = []
        for (_emp, _week), rows in sorted(groups.items(), key=lambda kv: (kv[0][1], kv[0][0]), reverse=True):
            first = rows.sorted('date')[0]
            week = _week_rows(rows)[0]
            out.append({
                'id': first.id, 'employee': ref(first.employee_id), 'currency': first.currency_id.name,
                'week_start': week['week_start'], 'week_end': week['week_end'], 'total': week['total'],
                'outside_days': week['outside_days'], 'days': week['days'],
            })
        return ok(out)

    @api_route('/api/v1/approvals/da/<int:claim_id>/<string:decision>', methods=('POST',), manager=True)
    def decide(self, employee, claim_id, decision, **kw):
        """Approve or reject the whole week of the person this claim belongs to."""
        if decision not in ('approve', 'reject'):
            raise ApiError('decision must be "approve" or "reject".')
        Claim = request.env['ff.da.claim'].sudo()
        claim = Claim.browse(claim_id).exists()
        if not claim or claim.employee_id not in employee._ff_subordinates():
            raise ApiError('Allowance not found.', 404, 'not_found')
        week = Claim.search([('employee_id', '=', claim.employee_id.id), ('week_start', '=', claim.week_start),
                             ('state', '=', 'submitted')])
        week.ff_decide_week(employee, decision == 'approve')
        note_rejection(week, decision == 'approve', employee)
        return ok({'decided': len(week), 'state': 'approved' if decision == 'approve' else 'rejected'})
