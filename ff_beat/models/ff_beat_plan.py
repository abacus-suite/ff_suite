from odoo import api, fields, models
from odoo.exceptions import ValidationError

from .ff_route_plan import month_start


class FfBeatPlan(models.Model):
    """One route on one day, with the customers planned on it."""
    _name = 'ff.beat.plan'
    _description = 'Daily Route Plan'
    _order = 'date desc, employee_id, id'

    plan_id = fields.Many2one('ff.route.plan', string='Monthly Plan', index=True, ondelete='cascade')
    employee_id = fields.Many2one('hr.employee', required=True, index=True, ondelete='cascade')
    team_id = fields.Many2one(related='employee_id.ff_team_id', store=True)
    department_id = fields.Many2one(related='employee_id.department_id', store=True)
    employee_route_ids = fields.Many2many(related='employee_id.ff_route_ids', string='Allowed Routes')
    beat_id = fields.Many2one('ff.beat', string='Route', required=True, ondelete='restrict')
    route_type_id = fields.Many2one(related='beat_id.route_type_id', store=True)
    district_id = fields.Many2one(related='beat_id.district_id', store=True)
    date = fields.Date(required=True, index=True, default=fields.Date.context_today)
    customer_line_ids = fields.One2many('ff.route.plan.customer', 'day_id', string='Customers', copy=True)
    visit_ids = fields.One2many('ff.visit', 'beat_plan_id', string='Visits')

    planned_count = fields.Integer(string='Planned', compute='_compute_stats', store=True)
    completed_count = fields.Integer(string='Visited', compute='_compute_stats', store=True)
    missed_count = fields.Integer(string='Missed', compute='_compute_stats', store=True)
    cancelled_count = fields.Integer(string='Cancelled', compute='_compute_stats', store=True)
    adhoc_count = fields.Integer(string='Adhoc', compute='_compute_stats', store=True)
    total_visits = fields.Integer(string='Total Visits', compute='_compute_stats', store=True)
    completion_pct = fields.Float(string='Completion %', digits=(5, 1), compute='_compute_stats', store=True)

    planned_km = fields.Float(related='beat_id.planned_km', string='Planned km')
    actual_km = fields.Float(string='Actual km', digits=(10, 1), compute='_compute_km')
    deviation_km = fields.Float(string='Deviation km', digits=(10, 1), compute='_compute_km',
                                help='Actual GPS distance minus planned route distance.')
    status = fields.Selection([
        ('planned', 'Planned'),
        ('in_progress', 'In Progress'),
        ('done', 'Completed'),
        ('missed', 'Missed'),
    ], compute='_compute_status')

    _employee_date_beat_uniq = models.Constraint(
        'UNIQUE(employee_id, date, beat_id)', 'This route is already planned for the employee on that day.')

    @api.constrains('employee_id', 'beat_id')
    def _check_assigned_route(self):
        for day in self:
            routes = day.employee_id.sudo().ff_route_ids
            if routes and day.beat_id not in routes:
                raise ValidationError(self.env._(
                    '%(route)s is not assigned to %(employee)s. Add it to the employee\'s Assigned Routes first.',
                    route=day.beat_id.display_name, employee=day.employee_id.name))

    @api.constrains('employee_id', 'date')
    def _check_routes_per_day(self):
        for day in self:
            employee = day.employee_id.sudo()
            if employee.ff_routes_per_day == 'single' and self.sudo().search_count(
                    [('employee_id', '=', employee.id), ('date', '=', day.date)]) > 1:
                raise ValidationError(self.env._(
                    '%(employee)s works one route per day (%(date)s). Set "Routes per Day" to several on the employee to plan more.',
                    employee=employee.name, date=day.date))

    @api.constrains('plan_id', 'date', 'employee_id')
    def _check_plan_month(self):
        for day in self:
            plan = day.plan_id
            if plan and (plan.employee_id != day.employee_id or month_start(day.date) != plan.month):
                raise ValidationError(self.env._('%(date)s is outside the monthly plan "%(plan)s".',
                                                 date=day.date, plan=plan.name))

    @api.depends('employee_id', 'beat_id', 'date')
    def _compute_display_name(self):
        for day in self:
            day.display_name = '%s - %s (%s)' % (day.employee_id.name or '', day.beat_id.display_name or '', day.date or '')

    @api.depends('customer_line_ids.status', 'customer_line_ids.selected', 'visit_ids.partner_id')
    def _compute_stats(self):
        for day in self:
            lines = day.customer_line_ids.filtered('selected')
            statuses = lines.mapped('status')
            day.planned_count = len(lines)
            day.completed_count = statuses.count('visited')
            day.missed_count = statuses.count('missed')
            day.cancelled_count = statuses.count('cancelled')
            day.adhoc_count = len(day.visit_ids.partner_id - lines.partner_id)
            day.total_visits = len(day.visit_ids)
            due = len(lines) - day.cancelled_count
            day.completion_pct = 100.0 * day.completed_count / due if due else 0.0

    def _compute_km(self):
        tracks = {(t.employee_id.id, t.date): t.distance_km for t in self.env['ff.daily.track'].sudo().search([
            ('employee_id', 'in', self.employee_id.ids), ('date', 'in', self.mapped('date')),
        ])}
        for day in self:
            day.actual_km = tracks.get((day.employee_id.id, day.date), 0.0)
            day.deviation_km = day.actual_km - day.planned_km if day.actual_km else 0.0

    def _compute_status(self):
        today = fields.Date.context_today(self)
        for day in self:
            due = day.planned_count - day.cancelled_count
            if day.planned_count and day.completed_count >= due:
                day.status = 'done'
            elif day.total_visits:
                day.status = 'in_progress'
            elif day.date and day.date < today:
                day.status = 'missed'
            else:
                day.status = 'planned'

    @api.onchange('beat_id')
    def _onchange_beat_id(self):
        self.customer_line_ids = [(5, 0, 0)] + self._ff_customer_line_cmds(self.beat_id)

    @api.model
    def _ff_customer_line_cmds(self, route, selected_partners=None):
        """All customers of ``route``; ticked unless ``selected_partners`` excludes them."""
        return [(0, 0, {
            'partner_id': line.partner_id.id,
            'sequence': line.sequence,
            'selected': selected_partners is None or line.partner_id in selected_partners,
        }) for line in route.sudo().line_ids.sorted('sequence')]

    @api.model_create_multi
    def create(self, vals_list):
        RoutePlan = self.env['ff.route.plan']
        Employee = self.env['hr.employee'].sudo()
        Route = self.env['ff.beat'].sudo()
        for vals in vals_list:
            if not vals.get('plan_id') and vals.get('employee_id') and vals.get('date'):
                employee = Employee.browse(vals['employee_id'])
                vals['plan_id'] = RoutePlan._ff_get(employee, fields.Date.to_date(vals['date'])).id
            if 'customer_line_ids' not in vals and vals.get('beat_id'):
                vals['customer_line_ids'] = self._ff_customer_line_cmds(Route.browse(vals['beat_id']))
        days = super().create(vals_list)
        days._ff_link_visits()
        return days

    def write(self, vals):
        if vals.get('beat_id') and 'customer_line_ids' not in vals:
            route = self.env['ff.beat'].sudo().browse(vals['beat_id'])
            vals = dict(vals, customer_line_ids=[(5, 0, 0)] + self._ff_customer_line_cmds(route))
        if ('date' in vals or 'employee_id' in vals) and 'plan_id' not in vals:
            for day in self:
                employee = self.env['hr.employee'].sudo().browse(vals.get('employee_id') or day.employee_id.id)
                date = fields.Date.to_date(vals.get('date')) or day.date
                plan = self.env['ff.route.plan']._ff_get(employee, date)
                super(FfBeatPlan, day).write(dict(vals, plan_id=plan.id))
            res = True
        else:
            res = super().write(vals)
        if {'beat_id', 'date', 'employee_id', 'customer_line_ids'} & set(vals):
            self._ff_link_visits()
        return res

    def _ff_link_visits(self):
        """Attach existing visits of that day to the planned customers."""
        Visit = self.env['ff.visit'].sudo()
        for day in self.sudo():
            start, end = day.employee_id._ff_day_bounds(day.date)
            visits = Visit.search([
                ('employee_id', '=', day.employee_id.id), ('check_in_at', '>=', start), ('check_in_at', '<', end),
            ])
            for line in day.customer_line_ids.filtered(lambda l: not l.visit_id):
                visit = visits.filtered(lambda v, p=line.partner_id: v.partner_id == p)[:1]
                if visit:
                    line.visit_id = visit
            visits.filtered(lambda v: not v.beat_plan_id and v.partner_id in day.customer_line_ids.partner_id).write(
                {'beat_plan_id': day.id})
