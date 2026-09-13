"""Targets in the Aixolo panel and in the app's report catalogue."""
from datetime import timedelta

from odoo import api, models

from odoo.addons.ff_app_reports.models.ff_app_report import MONEY, NUMBER, col

from .ff_target import METRICS, month_bounds


class FfDashboardTargets(models.AbstractModel):
    _inherit = 'ff.dashboard'

    @api.model
    def ff_target_report(self, period='month', filters=None):
        employees, start, _end, report = self._generic(period, filters, 'ff.target', 'employee_id', 'month')
        progress = self.env['ff.target'].ff_progress(employees, start)
        first, _last = month_bounds(start)
        rows = progress['rows']
        # Company, department and team targets sit above the people, when the filters leave them in view.
        upper = self.env['ff.target'].sudo().search([('month', '=', first), ('scope', '!=', 'employee')])
        if employees:
            upper = upper.filtered(lambda t: t._ff_members() & employees)
        upper_rows = [t.ff_row() for t in upper.sorted(lambda t: ['company', 'department', 'team'].index(t.scope))]

        def team(metric):
            target = sum(m['target'] for row in rows for m in row['metrics'] if m['key'] == metric)
            actual = sum(m['actual'] for row in rows for m in row['metrics'] if m['key'] == metric)
            return target, actual

        tiles = []
        colours = {'visits': '#1a56db', 'customers': '#7c5cfc', 'sales': '#16a34a', 'collections': '#0d9488'}
        for metric, _field, label, money in METRICS:
            target, actual = team(metric)
            tiles.append(self._tile(
                label, actual, colours[metric],
                'of %s · %d%%' % (self._fmt_target(target, money), round(actual * 100 / target) if target else 0),
                money=money))

        def metric_of(row, key, part):
            found = [m for m in row['metrics'] if m['key'] == key]
            return found[0][part] if found else None

        report.update({
            # Targets are monthly: the section always shows the month the period starts in.
            'period_label': first.strftime('%B %Y'),
            'start': first.isoformat(),
            'tiles': tiles,
            'charts': [
                self._bar('Achievement by employee', 'fa-bullseye',
                          [{'name': row['employee'], 'amount': row['achievement']} for row in
                           sorted(rows, key=lambda row: -row['achievement'])[:12]], money=False),
            ],
            'columns': [
                {'key': 'level', 'label': 'Level'},
                {'key': 'employee', 'label': 'For', 'bold': True},
                {'key': 'visits', 'label': 'Visits'},
                {'key': 'customers', 'label': 'New customers'},
                {'key': 'sales', 'label': 'Sales'},
                {'key': 'collections', 'label': 'Collections'},
                {'key': 'achievement', 'label': 'Achievement', 'progress': True},
                {'key': 'incentive', 'label': 'Incentive', 'end': True},
            ],
            'rows': [dict({
                'id': row['id'],
                'level': {'company': 'Company', 'department': 'Department', 'team': 'Team'}.get(row['scope'], 'Employee'),
                'employee': row['employee'],
                'achievement': row['achievement'],
                'incentive': self._fmt_target(row['incentive']['earned'], True) if row.get('incentive') else '–',
            }, **{
                metric: ('%s / %s' % (self._fmt_target(metric_of(row, metric, 'actual'), money),
                                      self._fmt_target(metric_of(row, metric, 'target'), money))
                         if metric_of(row, metric, 'target') else '–')
                for metric, _field, _label, money in METRICS
            }) for row in upper_rows + rows],
        })
        if not rows:
            report['empty_hint'] = 'No targets set for %s. Add them under Aixolo › Targets.' % first.strftime('%B %Y')
        return report

    def _fmt_target(self, value, money):
        if value is None:
            return '–'
        if money:
            symbol = self.env.company.currency_id.symbol or ''
            return '%s%s' % (symbol, '{:,.0f}'.format(value))
        return '{:,.0f}'.format(value)


class FfAppReportTargets(models.AbstractModel):
    _inherit = 'ff.app.report'

    def _definitions(self):
        defs = super()._definitions()
        columns = [col('month', 'Month'), col('employee', 'Employee')]
        for metric, _field, label, money in METRICS:
            kind = MONEY if money else NUMBER
            columns += [col('%s_target' % metric, '%s target' % label, kind),
                        col('%s_actual' % metric, '%s done' % label, kind, True)]
        columns.append(col('achievement', 'Achievement %', NUMBER))
        defs['targets'] = ('Targets', 'Monthly targets and how far each one got', 'flag', 'ff.target',
                           columns, self._targets)
        return defs

    def _targets(self, employees, start, end):
        rows = []
        month = start.replace(day=1)
        while month <= end:
            progress = self.env['ff.target'].ff_progress(employees, month)
            for row in progress['rows']:
                values = {'month': month.strftime('%b %Y'), 'employee': row['employee'],
                          'achievement': row['achievement']}
                for metric in row['metrics']:
                    values['%s_target' % metric['key']] = metric['target']
                    values['%s_actual' % metric['key']] = metric['actual']
                rows.append(values)
            month = (month.replace(day=28) + timedelta(days=4)).replace(day=1)
        return rows

