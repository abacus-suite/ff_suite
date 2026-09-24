"""Targets for the app: my month, my team's, the leaderboard, and splitting what I was given."""
from odoo import fields, http
from odoo.http import request

from odoo.addons.ff_mobile_api.controllers.common import ApiError, api_route, body, ok

from ..models.ff_target import METRICS, month_bounds


def _row_payload(row):
    return dict(row, employee={'id': row['employee_id'], 'name': row['employee']})


def _month(employee, month):
    try:
        return fields.Date.to_date(month) if month else employee._ff_today()
    except ValueError:
        raise ApiError('month must be YYYY-MM-DD.')


def _ref(scope, record):
    return {'scope': scope, 'id': record.id, 'name': record.name}


class FieldForceTargetsApi(http.Controller):

    @api_route('/api/v1/targets', methods=('GET',))
    def targets(self, employee, month=None, **kw):
        day = _month(employee, month)
        Target = request.env['ff.target']
        mine = Target.ff_progress(employee, day)
        team = employee._ff_subordinates()
        team_rows = Target.ff_progress(team, day)['rows'] if team else []
        return ok({
            'month': mine['month'],
            'currency': employee.company_id.currency_id.name,
            'me': _row_payload(mine['rows'][0]) if mine['rows'] else None,
            'team': [_row_payload(row) for row in team_rows],
        })

    @api_route('/api/v1/targets/leaderboard', methods=('GET',))
    def leaderboard(self, employee, month=None, scope=None, limit=None, **kw):
        """Top performers among the people I can see - or my own team for field staff."""
        day = _month(employee, month)
        people = employee._ff_scope_employees()
        if len(people) <= 1 and employee.ff_team_id:
            people = request.env['hr.employee'].sudo().search([('ff_team_id', '=', employee.ff_team_id.id)])
        rows = request.env['ff.target'].ff_leaderboard(people, day, limit=min(int(limit or 20), 100))
        me = next((row for row in request.env['ff.target'].ff_leaderboard(people, day, limit=1000)
                   if row['employee_id'] == employee.id), None)
        return ok({
            'month': month_bounds(day)[0].isoformat(),
            'currency': employee.company_id.currency_id.name,
            'rows': rows,
            'me': me,
        })

    @api_route('/api/v1/targets/splittable', methods=('GET',))
    def splittable(self, employee, month=None, **kw):
        """Targets I own (or that belong to people under me) that I may divide, with who they can go to."""
        day = _month(employee, month)
        Target = request.env['ff.target'].sudo()
        start = month_bounds(day)[0]
        candidates = Target.search([('month', '=', start), ('scope', '!=', 'company')])
        mine = candidates.filtered(lambda t: t.ff_can_split(employee))
        result = []
        field_of = {'employee': 'employee_id', 'team': 'team_id', 'department': 'department_id'}
        for target in mine:
            children = {(child.scope, child[field_of[child.scope]].id): child for child in target.child_ids}
            options = []
            for scope, record in Target.ff_split_options(employee, target):
                child = children.get((scope, record.id))
                options.append(dict(_ref(scope, record), **{
                    key: (child[field] if child else 0) for key, field, _label, _money in METRICS}))
            if not options:
                continue
            row = target.ff_row()
            row['options'] = options
            result.append(row)
        return ok({'month': start.isoformat(), 'currency': employee.company_id.currency_id.name, 'targets': result})

    @api_route('/api/v1/targets/<int:target_id>/split', methods=('POST',))
    def split(self, employee, target_id, **kw):
        target = request.env['ff.target'].sudo().browse(target_id).exists()
        if not target:
            raise ApiError('Target not found.', 404, 'not_found')
        target.ff_split(employee, body().get('allocations') or [])
        return ok(target.ff_row())
