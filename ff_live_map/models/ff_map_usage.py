"""How many Google Maps requests this deployment has made, and what they cost.

Google bills two things we use: a map load in the Odoo web map, and a tile in
the phone app. Both are counted here as they happen, so the office can see the
month's usage against the free allowance without opening Cloud Console.
"""
import logging
from datetime import date

from odoo import api, fields, models

_logger = logging.getLogger(__name__)

KINDS = [
    ('web_map', 'Odoo Map Load'),
    ('tiles', 'App Map Tiles'),
    ('session', 'App Tile Session'),
    ('geocode', 'Address Lookup'),
]

# What Google gives away each month, and what it charges after that (per 1000).
# Both are editable in Settings because Google changes them from time to time.
DEFAULTS = {
    'map_free_loads': 10000,
    'map_free_tiles': 100000,
    'map_free_geocode': 10000,
    'map_price_loads': 620.0,   # per 1000 map loads beyond the free tier
    'map_price_tiles': 53.0,    # per 1000 tiles beyond the free tier
    'map_price_geocode': 440.0,  # per 1000 address lookups beyond the free tier
    'map_budget': 0.0,          # 0 = no budget set
    'map_guard_percent': 90,    # stop using Google at this share of the free tier
}

# Which free allowance each kind of request draws from.
GUARDED = {'tiles': 'map_free_tiles', 'web_map': 'map_free_loads', 'geocode': 'map_free_geocode'}


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
    def ff_guard_on(self):
        """Stay within Google's free tier: on unless the office switched it off."""
        return self.env['ir.config_parameter'].sudo().get_param('ff_base.map_free_guard', 'True') != 'False'

    @api.model
    def ff_google_allowed(self, kind):
        """May Google still be used for ``kind`` this month without paying?

        With the guard on, Google stops at the set share of the free allowance
        and the free maps take over until the 1st of next month.
        """
        if kind not in GUARDED or not self.ff_guard_on():
            return True
        free = map_setting(self.env, GUARDED[kind])
        percent = min(max(map_setting(self.env, 'map_guard_percent'), 1), 100)
        first, last = self._ff_month_bounds()
        groups = self.sudo()._read_group(
            [('date', '>=', first), ('date', '<', last), ('kind', '=', kind)], [], ['count:sum'])
        used = (groups[0][0] if groups else 0) or 0
        return used < free * percent / 100.0

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
                'tiles': 0, 'web_map': 0, 'session': 0, 'geocode': 0,
            })
            row[kind] = total
        ordered = sorted(rows.values(), key=lambda row: -(row['tiles'] + row['web_map']))
        return ordered

    @api.model
    def _ff_month_bounds(self, month=None):
        """The month asked for, or this one when the caller sends nonsense."""
        first = fields.Date.context_today(self)
        if month:
            try:
                first = fields.Date.to_date(month) or first
            except ValueError:
                _logger.warning('Field Force: ignoring an unreadable month (%s)', month)
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
        geocode = line('geocode', map_setting(self.env, 'map_free_geocode'), map_setting(self.env, 'map_price_geocode'))
        budget = map_setting(self.env, 'map_budget')
        cost = round(loads['cost'] + tiles['cost'] + geocode['cost'], 2)
        guard = self.ff_guard_on()
        return {
            'guard': guard,
            'guard_percent': map_setting(self.env, 'map_guard_percent'),
            'google_paused': {kind: guard and not self.ff_google_allowed(kind)
                              for kind in GUARDED} if first == self._ff_month_bounds()[0] else {},
            'month': first.strftime('%Y-%m'),
            'month_label': first.strftime('%B %Y'),
            'currency': self.env.company.currency_id.symbol or self.env.company.currency_id.name,
            'web_map': loads,
            'tiles': tiles,
            'geocode': geocode,
            'sessions': used.get('session', 0),
            'cost': cost,
            'budget': budget,
            'budget_left': round(budget - cost, 2) if budget else 0.0,
            'over_budget': bool(budget) and cost > budget,
            'by_employee': self.ff_usage_by_employee(month),
        }
