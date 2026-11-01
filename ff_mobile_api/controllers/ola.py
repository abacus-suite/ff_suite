"""OLA: the person's days of the month and the month total."""
import calendar
from datetime import date as date_type, timedelta

from odoo import http
from odoo.http import request

from .common import ApiError, api_route, ok


class FieldForceOlaApi(http.Controller):

    @api_route('/api/v1/ola', methods=('GET',))
    def my_ola(self, employee, month=None, **kw):
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
        Claim = env['ff.ola.claim']
        day = max(first, today - timedelta(days=4))
        while day <= min(last, today):
            Claim._ff_compute(employee, day)
            day += timedelta(days=1)
        rows = Claim.sudo().search([('employee_id', '=', employee.id), ('date', '>=', first), ('date', '<=', last)],
                                   order='date')
        params = Claim._ff_params()
        monthly = employee.sudo().ff_ola_monthly or params['monthly']
        per_day = round(monthly / (params['days'] or 26), 2)
        return ok({
            'month': first.strftime('%Y-%m'),
            'currency': employee.company_id.currency_id.name,
            'applicable': bool(employee.sudo().ff_ola_applicable),
            'monthly': monthly, 'per_day': per_day, 'half_day': round(per_day / 2, 2),
            'half_hours': params['half'], 'full_hours': params['full'],
            'total': round(sum(rows.mapped('amount')), 2),
            'days': [{'date': r.date.isoformat(), 'hours': r.hours, 'kind': r.kind, 'amount': r.amount}
                     for r in rows],
        })
