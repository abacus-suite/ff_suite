"""Targets for the app: my month, and my team's when I have one."""
from odoo import fields, http
from odoo.http import request

from odoo.addons.ff_mobile_api.controllers.common import ApiError, api_route, ok


def _row_payload(row):
    return {'employee': {'id': row['employee_id'], 'name': row['employee']},
            'achievement': row['achievement'], 'metrics': row['metrics']}


class FieldForceTargetsApi(http.Controller):

    @api_route('/api/v1/targets', methods=('GET',))
    def targets(self, employee, month=None, **kw):
        try:
            day = fields.Date.to_date(month) if month else employee._ff_today()
        except ValueError:
            raise ApiError('month must be YYYY-MM-DD.')
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
