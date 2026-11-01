"""Manager mode: give bottles and outlets targets, and see the team against them."""
import calendar

from odoo import fields, http
from odoo.http import request

from odoo.addons.ff_mobile_api.controllers.common import ApiError, api_route, body, ok

from ..models.ff_field_target import week_bounds


def _month_start(employee, month):
    try:
        day = fields.Date.to_date(month) if month else employee._ff_today()
    except ValueError:
        raise ApiError('month must be YYYY-MM-DD.')
    return day.replace(day=1)


class FieldForceFieldTargetsApi(http.Controller):

    @api_route('/api/v1/targets/assign', methods=('POST',), manager=True)
    def assign(self, employee, **kw):
        """One bottles and outlets target to each of the chosen people, monthly or for a week."""
        data = body()
        team = employee._ff_subordinates()
        ids = [int(i) for i in (data.get('employee_ids') or [])]
        people = team.filtered(lambda p: p.id in ids)
        if not people:
            raise ApiError('Choose at least one person in your team.', 400, 'invalid')
        period = 'week' if data.get('period') == 'week' else 'month'
        week = int(data.get('week') or 0) if period == 'week' else 0
        month = _month_start(employee, data.get('month'))
        bottles = int(data.get('bottles') or 0)
        outlets = int(data.get('outlets') or 0)
        if bottles <= 0 or outlets <= 0:
            raise ApiError('Enter the number of bottles and of outlets.', 400, 'invalid')
        Target = request.env['ff.field.target'].sudo()
        made = 0
        for person in people:
            existing = Target.search([('employee_id', '=', person.id), ('month', '=', month),
                                      ('period', '=', period), ('week', '=', week)], limit=1)
            values = {'bottle_target': bottles, 'outlet_target': outlets, 'assigned_by_id': employee.id}
            if existing:
                existing.write(values)
            else:
                Target.create(dict(values, employee_id=person.id, period=period, week=week, month=month))
            made += 1
            if 'ff.notification' in request.env:
                request.env['ff.notification'].sudo().ff_push(
                    request.env._('New target'),
                    request.env._('%(b)s bottles and %(o)s outlets (%(when)s).', b=bottles, o=outlets,
                                  when=month.strftime('%B %Y') + (' · week %s' % week if week else '')),
                    kind='info', employee=person)
        return ok({'assigned': made})

    @api_route('/api/v1/team/target', methods=('GET',), manager=True)
    def team_target(self, employee, month=None, view='month', **kw):
        """Month to date or one week: the team's bottles and outlets, each person against their own
        target, and each person's share of the team's."""
        first = _month_start(employee, month)
        week = int(view) if str(view) in ('1', '2', '3', '4') else 0
        start, end = (week_bounds(first, week) if week else
                      (first, first.replace(day=calendar.monthrange(first.year, first.month)[1])))
        today = employee._ff_today()
        end_actual = min(end, today) if first.year == today.year and first.month == today.month else end
        team = employee._ff_subordinates()
        Target = request.env['ff.field.target'].sudo()
        rows = []
        team_bottle_target = team_outlet_target = 0
        team_bottles = team_outlets = 0
        for person in team.sorted('name'):
            target = Target.search([('employee_id', '=', person.id), ('month', '=', first),
                                    ('period', '=', 'week' if week else 'month'), ('week', '=', week)], limit=1)
            actual = Target.ff_actual(person, start, end_actual)
            rows.append({
                'employee': {'id': person.id, 'name': person.name},
                'bottles': actual['bottles'], 'bottle_target': target.bottle_target if target else 0,
                'outlets': actual['outlets'], 'outlet_target': target.outlet_target if target else 0,
            })
            team_bottle_target += target.bottle_target if target else 0
            team_outlet_target += target.outlet_target if target else 0
            team_bottles += actual['bottles']
            team_outlets += actual['outlets']
        for row in rows:
            row['bottle_percent'] = round(row['bottles'] * 100.0 / row['bottle_target']) if row['bottle_target'] else 0
            row['outlet_percent'] = round(row['outlets'] * 100.0 / row['outlet_target']) if row['outlet_target'] else 0
            row['share'] = round(row['bottles'] * 100.0 / team_bottle_target, 1) if team_bottle_target else 0
        rows.sort(key=lambda r: (-r['bottle_percent'], r['employee']['name']))
        return ok({
            'month': first.isoformat(), 'view': 'month' if not week else str(week),
            'from': start.isoformat(), 'to': end.isoformat(),
            'bottles': team_bottles, 'bottle_target': team_bottle_target,
            'outlets': team_outlets, 'outlet_target': team_outlet_target,
            'rows': rows,
        })
