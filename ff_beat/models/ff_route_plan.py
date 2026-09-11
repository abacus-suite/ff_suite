import calendar
from datetime import timedelta

from odoo import api, fields, models
from odoo.exceptions import UserError


def month_start(day):
    return day.replace(day=1)


def month_end(day):
    return day.replace(day=calendar.monthrange(day.year, day.month)[1])


def week_of_month(day):
    return (day.day - 1) // 7 + 1


def is_week_off(employee, day):
    shift = employee.ff_shift_id
    return shift._ff_is_week_off(day) if shift else day.weekday() == 6


class FfRoutePlan(models.Model):
    """Monthly journey plan of one employee: "Ravi - May 2026 Plan"."""
    _name = 'ff.route.plan'
    _description = 'Monthly Route Plan'
    _inherit = ['mail.thread', 'mail.activity.mixin']
    _order = 'month desc, employee_id'

    name = fields.Char(compute='_compute_name', store=True)
    employee_id = fields.Many2one('hr.employee', required=True, index=True, ondelete='cascade', tracking=True)
    department_id = fields.Many2one(related='employee_id.department_id', store=True)
    team_id = fields.Many2one(related='employee_id.ff_team_id', store=True)
    company_id = fields.Many2one(related='employee_id.company_id', store=True)
    employee_route_ids = fields.Many2many(related='employee_id.ff_route_ids', string='Allowed Routes')
    routes_per_day = fields.Selection(related='employee_id.ff_routes_per_day')
    month = fields.Date(required=True, index=True, tracking=True,
                        default=lambda self: month_start(fields.Date.context_today(self)),
                        help='Any date of the month; stored as the first day.')
    month_label = fields.Char(string='Month', compute='_compute_name', store=True)
    state = fields.Selection([('draft', 'Draft'), ('confirmed', 'Confirmed')], default='draft',
                             required=True, tracking=True)
    day_ids = fields.One2many('ff.beat.plan', 'plan_id', string='Planned Days')
    customer_line_ids = fields.One2many('ff.route.plan.customer', 'plan_id', string='Planned Visits')
    planned_count = fields.Integer(string='Planned', compute='_compute_stats', store=True)
    visited_count = fields.Integer(string='Visited', compute='_compute_stats', store=True)
    missed_count = fields.Integer(string='Missed', compute='_compute_stats', store=True)
    cancelled_count = fields.Integer(string='Cancelled', compute='_compute_stats', store=True)
    completion_pct = fields.Float(string='Completion %', digits=(5, 1), compute='_compute_stats', store=True)
    note = fields.Text()

    _employee_month_uniq = models.Constraint('UNIQUE(employee_id, month)', 'An employee has one route plan per month.')

    @api.depends('employee_id.name', 'month')
    def _compute_name(self):
        for plan in self:
            plan.month_label = plan.month.strftime('%B %Y') if plan.month else False
            plan.name = '%s - %s Plan' % (plan.employee_id.name or '', plan.month_label or '')

    @api.depends('customer_line_ids.status')
    def _compute_stats(self):
        for plan in self:
            statuses = plan.customer_line_ids.mapped('status')
            planned = len([s for s in statuses if s != 'skipped'])
            plan.planned_count = planned
            plan.visited_count = statuses.count('visited')
            plan.missed_count = statuses.count('missed')
            plan.cancelled_count = statuses.count('cancelled')
            due = planned - plan.cancelled_count
            plan.completion_pct = 100.0 * plan.visited_count / due if due else 0.0

    @api.model_create_multi
    def create(self, vals_list):
        for vals in vals_list:
            if vals.get('month'):
                vals['month'] = month_start(fields.Date.to_date(vals['month']))
        return super().create(vals_list)

    def write(self, vals):
        if vals.get('month'):
            vals['month'] = month_start(fields.Date.to_date(vals['month']))
        return super().write(vals)

    @api.model
    def _ff_get(self, employee, day):
        """Monthly plan of ``employee`` containing ``day`` (created when missing)."""
        Plan = self.sudo()
        start = month_start(day)
        plan = Plan.search([('employee_id', '=', employee.id), ('month', '=', start)], limit=1)
        return plan or Plan.create({'employee_id': employee.id, 'month': start})

    def _ff_fill(self, routes_for_day, date_from, date_to, overwrite=False, skip_week_off=True):
        """Create daily plans for the employee. ``routes_for_day(day)`` returns
        [(route, selected partners or None for all)]. Returns days created."""
        self.ensure_one()
        Day = self.env['ff.beat.plan']
        employee = self.employee_id.sudo()
        created = 0
        day = date_from
        while day <= date_to:
            entries = routes_for_day(day)
            if employee.ff_routes_per_day == 'single':
                entries = entries[:1]
            if entries and not (skip_week_off and is_week_off(employee, day)):
                existing = Day.search([('employee_id', '=', employee.id), ('date', '=', day)])
                if existing and overwrite:
                    existing.filtered(lambda d: not d.visit_ids).unlink()
                    existing = existing.exists()
                if not existing:
                    for route, partners in entries:
                        Day.create({
                            'employee_id': employee.id,
                            'beat_id': route.id,
                            'date': day,
                            'customer_line_ids': Day._ff_customer_line_cmds(route, partners),
                        })
                        created += 1
            day += timedelta(days=1)
        return created

    def action_confirm(self):
        self.write({'state': 'confirmed'})

    def action_reset_draft(self):
        self.write({'state': 'draft'})

    def action_open_apply_template(self):
        self.ensure_one()
        return {
            'type': 'ir.actions.act_window',
            'name': self.env._('Apply Plan Template'),
            'res_model': 'ff.route.plan.apply.wizard',
            'view_mode': 'form',
            'target': 'new',
            'context': {
                'default_employee_ids': [(6, 0, self.employee_id.ids)],
                'default_date_from': self.month,
                'default_date_to': month_end(self.month),
            },
        }

    def action_copy_previous_month(self):
        """Repeat last month's pattern (same weekday of the same week of the month)."""
        self.ensure_one()
        previous = self.search([
            ('employee_id', '=', self.employee_id.id),
            ('month', '=', month_start(self.month - timedelta(days=1))),
        ], limit=1)
        if not previous.day_ids:
            raise UserError(self.env._('There is no plan for the previous month to copy.'))
        pattern = {}
        for day in previous.day_ids.sorted('date'):
            key = (week_of_month(day.date), day.date.weekday())
            pattern.setdefault(key, []).append((day.beat_id, day.customer_line_ids.filtered('selected').partner_id))
        created = self._ff_fill(lambda d: pattern.get((week_of_month(d), d.weekday()), []),
                                self.month, month_end(self.month))
        return {
            'type': 'ir.actions.client',
            'tag': 'display_notification',
            'params': {
                'type': 'success',
                'message': self.env._('%s days copied from %s.', created, previous.month_label),
                'next': {'type': 'ir.actions.client', 'tag': 'soft_reload'},
            },
        }
