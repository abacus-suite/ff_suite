"""Standing work: one rule that hands out the same task again and again.

The office writes the rule once - "every 15th, count the stock at every outlet
you visited" - and says who it is for: named people, whole teams, departments,
or everybody. It can also be about customers: a task per outlet, per lead, per
beat, per city. A scheduled run then creates the tasks on the days the rule
asks for, and nobody has to remember.

A task that was not done by its date is not simply forgotten: it is marked
missed, and the person is asked when they will do it. Their answer is kept on
the task, so the office sees both the slip and the promise.
"""
from datetime import timedelta

from dateutil.relativedelta import relativedelta

from odoo import api, fields, models
from odoo.exceptions import UserError, ValidationError

WEEKDAYS = [
    ('0', 'Monday'), ('1', 'Tuesday'), ('2', 'Wednesday'), ('3', 'Thursday'),
    ('4', 'Friday'), ('5', 'Saturday'), ('6', 'Sunday'),
]

ASSIGN_MODES = [
    ('employees', 'Chosen people'),
    ('teams', 'Whole teams'),
    ('departments', 'Whole departments'),
    ('all', 'Everybody in the field'),
]

CUSTOMER_MODES = [
    ('none', 'One task per person'),
    ('visited', 'One per customer they visited'),
    ('assigned', 'One per customer assigned to them'),
    ('route', 'One per customer on their routes'),
]

REPEATS = [
    ('once', 'Once'),
    ('daily', 'Every day'),
    ('weekly', 'Weekly, on chosen days'),
    ('monthly', 'Monthly, on a chosen date'),
    ('months', 'Every few months'),
    ('yearly', 'Yearly'),
]


class FfTaskPlan(models.Model):
    _name = 'ff.task.plan'
    _description = 'Recurring Field Task'
    _inherit = ['mail.thread']
    _order = 'name'

    name = fields.Char(string='Task', required=True, tracking=True,
                       help='What the person has to do, for example "Count the stock".')
    description = fields.Text(help='Anything the person needs to know to do it.')
    active = fields.Boolean(default=True)
    company_id = fields.Many2one('res.company', required=True, default=lambda self: self.env.company)

    # -- who it is for -------------------------------------------------
    assign_mode = fields.Selection(ASSIGN_MODES, string='Given to', default='employees', required=True,
                                   tracking=True)
    employee_ids = fields.Many2many('hr.employee', string='People')
    team_ids = fields.Many2many('ff.team', string='Teams')
    department_ids = fields.Many2many('hr.department', string='Departments')

    # -- which customers, when the task is about customers -------------
    customer_mode = fields.Selection(CUSTOMER_MODES, string='About', default='none', required=True,
                                     tracking=True)
    category_ids = fields.Many2many('ff.contact.category', string='Contact types',
                                    help='Outlets, leads, distributors... Leave empty for every type.')
    route_ids = fields.Many2many('ff.beat', string='Beats',
                                 help='Only customers on these beats. Leave empty for all.')
    district_ids = fields.Many2many('ff.district', string='Cities',
                                    help='Only customers in these cities. Leave empty for all.')
    visited_within_days = fields.Integer(string='Visited in the last (days)', default=30,
                                         help='For "one per customer they visited": how far back to look.')
    max_customers = fields.Integer(string='At most (customers)', default=0,
                                   help='0 = no limit. Keeps a rule from creating hundreds of tasks.')

    # -- when ----------------------------------------------------------
    repeat = fields.Selection(REPEATS, string='Repeat', default='monthly', required=True, tracking=True)
    interval = fields.Integer(string='Every', default=1,
                              help='Every 2 weeks, every 3 months... 1 means every time.')
    weekday_ids = fields.Char(string='Days of the week', default='0',
                              help='For weekly: 0 is Monday, comma separated. "0,2,4" is Mon, Wed and Fri.')
    month_day = fields.Integer(string='Day of the month', default=15,
                               help='For monthly and yearly rules; 31 means the last day of the month.')
    month = fields.Selection([(str(i), name) for i, name in enumerate(
        ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September',
         'October', 'November', 'December'], start=1)], string='Month', default='1',
        help='For a yearly rule.')
    date_start = fields.Date(string='Starts', default=fields.Date.context_today, required=True)
    date_end = fields.Date(string='Ends', help='Leave empty to keep going.')
    due_in_days = fields.Integer(string='Due within (days)', default=0,
                                 help='0 = due the day it is created.')

    # -- the task it makes ---------------------------------------------
    priority = fields.Selection([('0', 'Normal'), ('1', 'High'), ('2', 'Urgent')], default='0')
    requires_photo = fields.Boolean(string='Photo required to finish')

    # -- what happened -------------------------------------------------
    last_run = fields.Date(string='Last created', readonly=True)
    next_run = fields.Date(string='Next due', compute='_compute_next_run', store=True, readonly=True)
    task_ids = fields.One2many('ff.task', 'plan_id', string='Tasks')
    task_count = fields.Integer(compute='_compute_counts')
    open_count = fields.Integer(string='Still open', compute='_compute_counts')
    missed_count = fields.Integer(string='Missed', compute='_compute_counts')

    @api.depends('task_ids.state')
    def _compute_counts(self):
        for plan in self:
            tasks = plan.task_ids
            plan.task_count = len(tasks)
            plan.open_count = len(tasks.filtered(lambda t: t.state in ('todo', 'in_progress')))
            plan.missed_count = len(tasks.filtered('is_missed'))

    @api.depends('repeat', 'interval', 'weekday_ids', 'month_day', 'month', 'date_start', 'date_end', 'last_run')
    def _compute_next_run(self):
        for plan in self:
            plan.next_run = plan._next_date(fields.Date.context_today(plan))

    @api.constrains('interval', 'month_day')
    def _check_numbers(self):
        for plan in self:
            if plan.interval < 1:
                raise ValidationError(self.env._('"Every" must be 1 or more.'))
            if plan.repeat in ('monthly', 'yearly') and not 1 <= plan.month_day <= 31:
                raise ValidationError(self.env._('The day of the month must be between 1 and 31.'))

    # ------------------------------------------------------------------
    # When it runs
    # ------------------------------------------------------------------
    def _weekdays(self):
        self.ensure_one()
        days = [part.strip() for part in (self.weekday_ids or '').split(',') if part.strip().isdigit()]
        return sorted({int(day) % 7 for day in days}) or [0]

    def _due_on(self, day):
        """Is this rule due on ``day``?"""
        self.ensure_one()
        if day < self.date_start or (self.date_end and day > self.date_end):
            return False
        if self.repeat == 'once':
            return day == self.date_start
        if self.repeat == 'daily':
            return (day - self.date_start).days % max(self.interval, 1) == 0
        if self.repeat == 'weekly':
            if day.weekday() not in self._weekdays():
                return False
            weeks = ((day - self.date_start).days) // 7
            return weeks % max(self.interval, 1) == 0
        if self.repeat in ('monthly', 'months'):
            last_day = (day + relativedelta(day=31)).day
            wanted = min(self.month_day, last_day)
            if day.day != wanted:
                return False
            months = (day.year - self.date_start.year) * 12 + (day.month - self.date_start.month)
            step = max(self.interval, 1) if self.repeat == 'months' else 1
            return months % step == 0
        if self.repeat == 'yearly':
            last_day = (day + relativedelta(day=31)).day
            return day.month == int(self.month or 1) and day.day == min(self.month_day, last_day)
        return False

    def _next_date(self, after):
        """The next day this rule is due, looking ahead a year at most."""
        self.ensure_one()
        day = max(after, self.date_start)
        for _ in range(400):
            if self._due_on(day):
                return day
            day += timedelta(days=1)
            if self.date_end and day > self.date_end:
                return False
        return False

    # ------------------------------------------------------------------
    # Who it is for
    # ------------------------------------------------------------------
    def _people(self):
        self.ensure_one()
        Employee = self.env['hr.employee'].sudo()
        base = [('company_id', '=', self.company_id.id)]
        if self.assign_mode == 'employees':
            return self.employee_ids
        if self.assign_mode == 'teams':
            return Employee.search(base + [('ff_team_id', 'in', self.team_ids.ids)])
        if self.assign_mode == 'departments':
            return Employee.search(base + [('department_id', 'in', self.department_ids.ids)])
        return Employee.search(base + [('ff_is_field', '=', True)]) \
            if 'ff_is_field' in Employee._fields else Employee.search(base)

    def _customers_for(self, employee, day):
        """The customers this person gets a task for, under this rule."""
        self.ensure_one()
        Partner = self.env['res.partner'].sudo()
        if self.customer_mode == 'none':
            return Partner.browse()
        domain = [('ff_is_client', '=', True), ('ff_approval_state', '=', 'approved')]
        if self.category_ids:
            domain.append(('ff_category_id', 'in', self.category_ids.ids))
        if self.district_ids:
            domain.append(('ff_district_id', 'in', self.district_ids.ids))
        if self.customer_mode == 'assigned':
            domain.append(('ff_employee_ids', 'in', employee.ids))
        elif self.customer_mode == 'route':
            routes = self.route_ids or employee.sudo().ff_route_ids
            domain.append(('ff_route_ids', 'in', routes.ids))
        elif self.customer_mode == 'visited':
            since = day - timedelta(days=max(self.visited_within_days, 1))
            visits = self.env['ff.visit'].sudo().search([
                ('employee_id', '=', employee.id), ('check_in_at', '>=', fields.Datetime.to_datetime(since)),
            ])
            domain.append(('id', 'in', visits.partner_id.ids))
        if self.route_ids and self.customer_mode != 'route':
            domain.append(('ff_route_ids', 'in', self.route_ids.ids))
        partners = Partner.search(domain, limit=self.max_customers or None)
        return partners

    # ------------------------------------------------------------------
    # Making the tasks
    # ------------------------------------------------------------------
    def action_run_now(self):
        """Create today's tasks by hand, for testing a rule."""
        created = self._run(fields.Date.context_today(self), force=True)
        return {
            'type': 'ir.actions.client', 'tag': 'display_notification',
            'params': {'type': 'success', 'sticky': False,
                       'message': self.env._('%s task(s) created.', created)},
        }

    def _run(self, day, force=False):
        """Create the tasks this rule asks for on ``day``. Never twice."""
        Task = self.env['ff.task'].sudo()
        made = 0
        for plan in self:
            if not force and not plan._due_on(day):
                continue
            due = day + timedelta(days=max(plan.due_in_days, 0))
            for employee in plan._people():
                customers = plan._customers_for(employee, day)
                targets = customers or [False]
                for partner in targets:
                    exists = Task.search_count([
                        ('plan_id', '=', plan.id), ('employee_id', '=', employee.id),
                        ('partner_id', '=', partner.id if partner else False),
                        ('plan_day', '=', day),
                    ])
                    if exists:
                        continue
                    Task.create({
                        'name': plan.name,
                        'description': plan.description or False,
                        'employee_id': employee.id,
                        'partner_id': partner.id if partner else False,
                        'date_deadline': due,
                        'priority': plan.priority,
                        'requires_photo': plan.requires_photo,
                        'plan_id': plan.id,
                        'plan_day': day,
                    })
                    made += 1
            plan.last_run = day
        return made

    @api.model
    def _cron_create_tasks(self):
        """Runs daily: today's rules, and anything missed while the server slept."""
        today = fields.Date.context_today(self)
        plans = self.sudo().search([('active', '=', True)])
        for plan in plans:
            start = plan.last_run + timedelta(days=1) if plan.last_run else today
            day = max(start, plan.date_start)
            while day <= today:
                plan._run(day)
                day += timedelta(days=1)
        self.env['ff.task'].sudo()._cron_mark_missed()

    def action_open_tasks(self):
        self.ensure_one()
        return {
            'type': 'ir.actions.act_window',
            'name': self.name,
            'res_model': 'ff.task',
            'view_mode': 'list,form',
            'domain': [('plan_id', '=', self.id)],
            'context': {'search_default_group_state': 1},
        }


class FfTaskFromPlan(models.Model):
    _inherit = 'ff.task'

    plan_id = fields.Many2one('ff.task.plan', string='Standing task', index=True, ondelete='set null',
                              readonly=True)
    plan_day = fields.Date(string='Planned for', readonly=True, index=True,
                           help='The day the standing task asked for this one.')
    is_missed = fields.Boolean(string='Missed', readonly=True, index=True, tracking=True,
                               help='The due date passed with the task still open.')
    promised_date = fields.Date(string='Promised for', tracking=True,
                                help='When the person said they would do it after missing the date.')
    promised_note = fields.Char(string='Why it slipped', tracking=True)

    @api.model
    def _cron_mark_missed(self):
        """Anything still open after its date is marked missed, once."""
        today = fields.Date.context_today(self)
        late = self.sudo().search([
            ('state', 'in', ('todo', 'in_progress')), ('is_missed', '=', False),
            ('date_deadline', '<', today), ('date_deadline', '!=', False),
        ])
        for task in late:
            task.is_missed = True
            task.message_post(body=self.env._(
                'Not done by %(due)s. The app will ask when it can be done.', due=task.date_deadline))
        return len(late)

    def ff_promise(self, employee, date, note=''):
        """From the app: the person says when they will do a missed task."""
        self.ensure_one()
        if self.employee_id != employee:
            raise UserError(self.env._('This task is not yours.'))
        promised = fields.Date.to_date(date)
        if not promised:
            raise UserError(self.env._('Choose the day you will do it.'))
        if promised < fields.Date.context_today(self):
            raise UserError(self.env._('Choose today or a later day.'))
        self.sudo().write({
            'promised_date': promised,
            'promised_note': (note or '').strip()[:200] or False,
            'date_deadline': promised,
        })
        self.sudo().message_post(body=self.env._(
            '%(who)s will do this on %(day)s.%(why)s', who=employee.name, day=promised,
            why=' %s' % note if note else ''))
        return self.ff_app_payload() if hasattr(self, 'ff_app_payload') else True
