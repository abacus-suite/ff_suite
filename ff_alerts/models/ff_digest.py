"""The day (or week) in one email to each manager."""
from datetime import datetime, timedelta
from html import escape

import pytz

from odoo import api, fields, models

from .ff_alert import _param


class FfDigest(models.AbstractModel):
    _name = 'ff.digest'
    _description = 'Field Manager Email Digest'

    @api.model
    def _cron_send(self):
        """Runs hourly; sends when the local hour matches the setting, once per day or week."""
        send_daily = _param(self.env, 'digest_daily', True)
        send_weekly = _param(self.env, 'digest_weekly', True)
        if not (send_daily or send_weekly):
            return
        hour = _param(self.env, 'digest_hour', 20)
        tz = pytz.timezone(self.env['ir.config_parameter'].sudo().get_param('ff_base.default_tz')
                           or self.env.company.partner_id.tz or 'UTC')
        now = datetime.now(pytz.utc).astimezone(tz)
        if now.hour != hour:
            return
        today = now.date()
        Param = self.env['ir.config_parameter'].sudo()
        if send_daily and Param.get_param('ff_alerts.digest_daily_last') != today.isoformat():
            self._send_all(today, today, 'Daily summary')
            Param.set_param('ff_alerts.digest_daily_last', today.isoformat())
        # The weekly one goes out on Sunday evening, for Monday to Sunday.
        if send_weekly and today.weekday() == 6 and Param.get_param('ff_alerts.digest_weekly_last') != today.isoformat():
            self._send_all(today - timedelta(days=6), today, 'Weekly summary')
            Param.set_param('ff_alerts.digest_weekly_last', today.isoformat())

    def _managers(self):
        employees = self.env['hr.employee'].sudo().search([('ff_access_scope', '!=', 'own')])
        return employees.filtered(lambda e: (e.work_email or e.user_id.email) and e._ff_subordinates())

    @api.model
    def ff_send_now(self, manager=None, days=1):
        """Send a digest straight away (from settings, to check how it looks)."""
        managers = manager or self._managers()
        end = fields.Date.context_today(self)
        for person in managers:
            self._send_one(person, end - timedelta(days=days - 1), end, 'Summary')
        return len(managers)

    def _send_all(self, start, end, title):
        for manager in self._managers():
            self._send_one(manager, start, end, title)

    def _send_one(self, manager, start, end, title):
        team = manager._ff_subordinates()
        if not team:
            return
        rows = [self._row(employee, start, end) for employee in team.sorted('name')]
        email = manager.work_email or manager.user_id.email
        period = start.strftime('%d %b %Y') if start == end else '%s – %s' % (start.strftime('%d %b'), end.strftime('%d %b %Y'))
        subject = 'Field Force %s · %s · %d people' % (title.lower(), period, len(rows))
        self.env['mail.mail'].sudo().create({
            'subject': subject,
            'email_to': email,
            'email_from': self.env.company.email or self.env.user.email_formatted,
            'body_html': self._html(manager, title, period, rows),
            'auto_delete': True,
        }).send()

    # ------------------------------------------------------------------
    def _row(self, employee, start, end):
        env = self.env
        low = employee._ff_day_bounds(start)[0]
        high = employee._ff_day_bounds(end)[1]
        attendances = env['hr.attendance'].sudo().search([
            ('employee_id', '=', employee.id), ('check_in', '>=', low), ('check_in', '<', high)], order='check_in')
        visits = env['ff.visit'].sudo().search([
            ('employee_id', '=', employee.id), ('check_in_at', '>=', low), ('check_in_at', '<', high)])
        offsite = visits.filtered(lambda v: v.visit_type == 'offsite') if 'visit_type' in visits._fields else visits.browse()
        flow = env['ir.config_parameter'].sudo().get_param('ff_base.order_flow') or 'direct'
        if flow == 'demand' and 'ff.demand' in env:
            sales = env['ff.demand'].sudo().search([
                ('employee_id', '=', employee.id), ('date', '>=', low), ('date', '<', high), ('state', '!=', 'cancelled')])
            sales_value = sum(sales.mapped('amount_total'))
        else:
            sales = env['sale.order'].sudo().search([
                ('ff_employee_id', '=', employee.id), ('date_order', '>=', low), ('date_order', '<', high),
                ('state', '!=', 'cancel')])
            sales_value = sum(sales.mapped('amount_total'))
        collected = 0.0
        if 'ff.collection' in env:
            collected = sum(env['ff.collection'].sudo().search([
                ('employee_id', '=', employee.id), ('date', '>=', low), ('date', '<', high),
                ('state', '!=', 'cancelled')]).mapped('amount'))
        tasks_done = overdue = 0
        if 'ff.task' in env:
            Task = env['ff.task'].sudo()
            tasks_done = Task.search_count([('employee_id', '=', employee.id), ('done_at', '>=', low), ('done_at', '<', high)])
            overdue = Task.search_count([('employee_id', '=', employee.id), ('is_overdue', '=', True)])
        km = sum(env['ff.daily.track'].sudo().search([
            ('employee_id', '=', employee.id), ('date', '>=', start), ('date', '<=', end)]).mapped('distance_km'))
        alerts = env['ff.alert'].sudo().search_count([
            ('employee_id', '=', employee.id), ('create_date', '>=', low), ('create_date', '<', high)])
        first_in = employee._ff_to_local(attendances[0].check_in).strftime('%H:%M') if attendances else None
        return {
            'name': employee.name,
            'days': len({employee._ff_to_local(a.check_in).date() for a in attendances}),
            'first_in': first_in,
            'hours': round(sum(attendances.mapped('worked_hours')), 1),
            'visits': len(visits),
            'offsite': len(offsite),
            'sales': sales_value,
            'collected': collected,
            'km': round(km, 1),
            'tasks_done': tasks_done,
            'overdue': overdue,
            'alerts': alerts,
        }

    def _html(self, manager, title, period, rows):
        currency = self.env.company.currency_id.symbol or ''
        single_day = all(row['days'] <= 1 for row in rows)
        present = sum(1 for row in rows if row['days'])
        totals = {key: sum(row[key] for row in rows) for key in ('visits', 'offsite', 'sales', 'collected', 'tasks_done', 'alerts')}

        def money(value):
            return '%s%s' % (currency, '{:,.0f}'.format(value))

        cells = ''.join(
            '<tr style="border-top:1px solid #e3e9f6">'
            '<td style="padding:8px;font-weight:600">%s</td>'
            '<td style="padding:8px">%s</td>'
            '<td style="padding:8px;text-align:right">%s</td>'
            '<td style="padding:8px;text-align:right">%d%s</td>'
            '<td style="padding:8px;text-align:right">%s</td>'
            '<td style="padding:8px;text-align:right">%s</td>'
            '<td style="padding:8px;text-align:right">%s</td>'
            '<td style="padding:8px;text-align:right">%d%s</td>'
            '<td style="padding:8px;text-align:right;color:%s">%d</td>'
            '</tr>' % (
                escape(row['name']),
                (row['first_in'] or '<span style="color:#dc2626">Absent</span>') if single_day else '%d days' % row['days'],
                row['hours'],
                row['visits'], (' <span style="color:#dc2626">(%d off)</span>' % row['offsite']) if row['offsite'] else '',
                money(row['sales']), money(row['collected']), row['km'],
                row['tasks_done'], (' <span style="color:#dc2626">+%d late</span>' % row['overdue']) if row['overdue'] else '',
                '#dc2626' if row['alerts'] else '#6b7a99', row['alerts'],
            ) for row in rows)
        tile = ('<td style="padding:12px 16px;background:#f4f7fe;border-radius:12px">'
                '<div style="font-size:12px;color:#6b7a99">%s</div><div style="font-size:20px;font-weight:800">%s</div></td>')
        return (
            '<div style="font-family:Arial,sans-serif;color:#0f1b3d;max-width:900px">'
            '<h2 style="margin:0 0 4px">%s</h2><div style="color:#6b7a99;margin-bottom:16px">%s · for %s</div>'
            '<table style="border-spacing:8px;margin:0 -8px 12px"><tr>%s%s%s%s%s</tr></table>'
            '<table style="border-collapse:collapse;width:100%%;font-size:13px">'
            '<tr style="background:#e8efff;text-align:left">'
            '<th style="padding:8px">Employee</th><th style="padding:8px">%s</th><th style="padding:8px;text-align:right">Hours</th>'
            '<th style="padding:8px;text-align:right">Visits</th><th style="padding:8px;text-align:right">Sales</th>'
            '<th style="padding:8px;text-align:right">Collected</th><th style="padding:8px;text-align:right">Km</th>'
            '<th style="padding:8px;text-align:right">Tasks done</th><th style="padding:8px;text-align:right">Alerts</th></tr>'
            '%s</table>'
            '<p style="color:#6b7a99;font-size:12px;margin-top:16px">Sent by Field Force. Open the Field Force panel in Odoo for the detail.</p>'
            '</div>'
        ) % (
            escape(title), escape(period), escape(manager.name),
            tile % ('Present', '%d / %d' % (present, len(rows))),
            tile % ('Visits', '%d%s' % (totals['visits'], (' (%d offsite)' % totals['offsite']) if totals['offsite'] else '')),
            tile % ('Sales', money(totals['sales'])),
            tile % ('Collected', money(totals['collected'])),
            tile % ('Alerts', totals['alerts']),
            'First in' if single_day else 'Worked',
            cells,
        )
