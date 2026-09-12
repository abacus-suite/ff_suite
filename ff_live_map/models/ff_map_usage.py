"""How many Google Maps requests this deployment has made, and what they cost.

Google bills two things we use: a map load in the Odoo web map, and a tile in
the phone app. Both are counted here as they happen, so the office can see the
month's usage against the free allowance without opening Cloud Console.
"""
from datetime import date

from odoo import api, fields, models

KINDS = [
    ('web_map', 'Odoo Map Load'),
    ('tiles', 'App Map Tiles'),
    ('session', 'App Tile Session'),
]

# What Google gives away each month, and what it charges after that (per 1000).
# Both are editable in Settings because Google changes them from time to time.
DEFAULTS = {
    'map_free_loads': 10000,
    'map_free_tiles': 100000,
    'map_price_loads': 620.0,   # per 1000 map loads beyond the free tier
    'map_price_tiles': 53.0,    # per 1000 tiles beyond the free tier
    'map_budget': 0.0,          # 0 = no budget set
}


def map_setting(env, key):
    raw = env['ir.config_parameter'].sudo().get_param('ff_base.%s' % key)
    default = DEFAULTS[key]
    if raw in (None, False, ''):
        return default
    try:
        return type(default)(float(raw))
    except (TypeError, ValueError):
        return default


class FfMapUsage(models.Model):
    _name = 'ff.map.usage'
    _description = 'Google Maps Usage'
    _order = 'date desc, id desc'
    _rec_name = 'date'

    date = fields.Date(required=True, index=True, default=fields.Date.context_today)
    kind = fields.Selection(KINDS, required=True, index=True)
    user_id = fields.Many2one('res.users', string='Odoo User', index=True, ondelete='set null')
    employee_id = fields.Many2one('hr.employee', string='Field Employee', index=True, ondelete='set null')
    count = fields.Integer(string='Requests', default=0)
    company_id = fields.Many2one('res.company', default=lambda self: self.env.company)

    _one_row_per_day = models.Constraint(
        'UNIQUE(date, kind, user_id, employee_id)', 'Usage is counted once per day and user.')

    @api.model
    def ff_record(self, kind, count=1, employee=None, user=None):
        """Add ``count`` requests to today's row, creating it the first time."""
        count = max(int(count or 0), 0)
        if not count or kind not in dict(KINDS):
            return self.browse()
        Usage = self.sudo()
        today = fields.Date.context_today(self)
        user = user or (employee.user_id if employee else self.env.user)
        row = Usage.search([
            ('date', '=', today), ('kind', '=', kind),
            ('user_id', '=', user.id if user else False),
            ('employee_id', '=', employee.id if employee else False),
        ], limit=1)
        if row:
            row.count += count
        else:
            row = Usage.create({
                'date': today, 'kind': kind, 'count': count,
                'user_id': user.id if user else False,
                'employee_id': employee.id if employee else False,
            })
        return row

    @api.model
    def ff_record_web_map(self):
        """Called by the live map when it actually loads Google's script."""
        self.ff_record('web_map', 1)
        return self.ff_usage_summary()

    @api.model
    def ff_usage_by_employee(self, month=None):
        """Who used how much this month, biggest first."""
        first, last = self._ff_month_bounds(month)
        groups = self.sudo()._read_group(
            [('date', '>=', first), ('date', '<', last)], ['employee_id', 'kind'], ['count:sum'])
        rows = {}
        for employee, kind, total in groups:
            row = rows.setdefault(employee.id or 0, {
                'id': employee.id or 0,
                'name': employee.display_name or 'Odoo users',
                'tiles': 0, 'web_map': 0, 'session': 0,
            })
            row[kind] = total
        ordered = sorted(rows.values(), key=lambda row: -(row['tiles'] + row['web_map']))
        return ordered

    @api.model
    def _ff_month_bounds(self, month=None):
        first = fields.Date.to_date(month) if month else fields.Date.context_today(self)
        first = first.replace(day=1)
        return first, date(first.year + (first.month // 12), (first.month % 12) + 1, 1)

    @api.model
    def ff_usage_summary(self, month=None):
        """This month's usage, what is left of the free allowance and the cost."""
        first, last = self._ff_month_bounds(month)
        groups = self.sudo()._read_group(
            [('date', '>=', first), ('date', '<', last)], ['kind'], ['count:sum'])
        used = {kind: total for kind, total in groups}

        def line(kind, free, price):
            count = used.get(kind, 0)
            billable = max(count - free, 0)
            return {
                'used': count,
                'free': free,
                'free_left': max(free - count, 0),
                'billable': billable,
                'cost': round(billable * price / 1000.0, 2),
                'percent': round(min(count / free * 100.0, 100.0), 1) if free else 0.0,
            }

        loads = line('web_map', map_setting(self.env, 'map_free_loads'), map_setting(self.env, 'map_price_loads'))
        tiles = line('tiles', map_setting(self.env, 'map_free_tiles'), map_setting(self.env, 'map_price_tiles'))
        budget = map_setting(self.env, 'map_budget')
        cost = round(loads['cost'] + tiles['cost'], 2)
        return {
            'month': first.strftime('%Y-%m'),
            'month_label': first.strftime('%B %Y'),
            'currency': self.env.company.currency_id.symbol or self.env.company.currency_id.name,
            'web_map': loads,
            'tiles': tiles,
            'sessions': used.get('session', 0),
            'cost': cost,
            'budget': budget,
            'budget_left': round(budget - cost, 2) if budget else 0.0,
            'over_budget': bool(budget) and cost > budget,
            'by_employee': self.ff_usage_by_employee(month),
        }
