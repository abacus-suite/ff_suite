"""Monthly targets that flow down the organisation, and what was done against them.

A target belongs to the company, a department, a team or one employee. The
office sets the top ones; whoever owns a target (the department or team
manager, or an employee with people under them) can split it into targets
for the level below - down as far as the organisation goes. Achievement is
always what the people inside the target actually did.
"""
import calendar

from dateutil.relativedelta import relativedelta

from odoo import api, fields, models
from odoo.exceptions import UserError, ValidationError

# metric -> (target field, label, money?)
METRICS = [
    ('visits', 'visit_target', 'Visits', False),
    ('customers', 'customer_target', 'New customers', False),
    ('sales', 'sales_target', 'Sales', True),
    ('collections', 'collection_target', 'Collections', True),
]
TARGET_FIELDS = [field for _key, field, _label, _money in METRICS]
SCOPES = [
    ('company', 'Company'),
    ('department', 'Department'),
    ('team', 'Team'),
    ('employee', 'Employee'),
]


def month_bounds(day):
    first = day.replace(day=1)
    return first, first.replace(day=calendar.monthrange(first.year, first.month)[1])


def percent(actual, target):
    return round(actual * 100.0 / target) if target else 0


def target_param(env, key, default):
    return env['ir.config_parameter'].sudo().get_param('ff_targets.%s' % key) or default


class FfTarget(models.Model):
    _name = 'ff.target'
    _description = 'Monthly Target'
    _inherit = ['mail.thread']
    _order = 'month desc, scope, name'
    _parent_store = True

    name = fields.Char(compute='_compute_name', store=True)
    month = fields.Date(required=True, index=True, tracking=True,
                        default=lambda self: fields.Date.context_today(self).replace(day=1),
                        help='Any day in the month; saved as its first day.')
    scope = fields.Selection(SCOPES, required=True, default='employee', index=True, tracking=True)
    employee_id = fields.Many2one('hr.employee', index=True, ondelete='cascade', tracking=True)
    team_id = fields.Many2one('ff.team', string='Team', index=True, tracking=True,
                              compute='_compute_org', store=True, readonly=False)
    department_id = fields.Many2one('hr.department', string='Department', index=True, tracking=True,
                                    compute='_compute_org', store=True, readonly=False)
    company_id = fields.Many2one('res.company', required=True, index=True,
                                 compute='_compute_org', store=True, readonly=False,
                                 default=lambda self: self.env.company)
    currency_id = fields.Many2one(related='company_id.currency_id')

    parent_id = fields.Many2one('ff.target', string='Split From', index=True, ondelete='cascade', copy=False,
                                help='The target this one was carved out of.')
    parent_path = fields.Char(index=True)
    child_ids = fields.One2many('ff.target', 'parent_id', string='Split Into')
    owner_id = fields.Many2one('hr.employee', string='Owner', compute='_compute_owner', store=True,
                               help='Who answers for this target and may split it further.')
    assigned_by_id = fields.Many2one('hr.employee', string='Assigned By', readonly=True, copy=False)

    visit_target = fields.Integer(string='Visits', tracking=True)
    customer_target = fields.Integer(string='New Customers', tracking=True)
    sales_target = fields.Monetary(string='Sales', tracking=True,
                                   help='Order value, or demand value when the demand flow is on.')
    collection_target = fields.Monetary(string='Collections', tracking=True)
    note = fields.Char()

    visit_actual = fields.Integer(string='Visits Done', compute='_compute_actuals')
    customer_actual = fields.Integer(string='Customers Added', compute='_compute_actuals')
    sales_actual = fields.Monetary(string='Sales Done', compute='_compute_actuals')
    collection_actual = fields.Monetary(string='Collected', compute='_compute_actuals')
    achievement = fields.Integer(string='Achievement %', compute='_compute_actuals',
                                 help='Average of the metrics that have a target.')
    unallocated = fields.Char(compute='_compute_unallocated', string='Not Yet Split',
                              help='What is left of this target after splitting it.')

    incentive_rule_id = fields.Many2one('ff.incentive.rule', string='Incentive', tracking=True)
    incentive_earned = fields.Monetary(string='Incentive Earned', compute='_compute_incentive')
    incentive_status = fields.Char(compute='_compute_incentive')

    # ------------------------------------------------------------------
    # Who and where
    # ------------------------------------------------------------------
    @api.depends('scope', 'employee_id', 'team_id', 'department_id', 'month')
    def _compute_name(self):
        for target in self:
            who = {
                'company': target.company_id.name,
                'department': target.department_id.name,
                'team': target.team_id.name,
                'employee': target.employee_id.name,
            }.get(target.scope) or ''
            target.name = '%s - %s' % (who, target.month.strftime('%b %Y') if target.month else '')

    @api.depends('employee_id', 'scope')
    def _compute_org(self):
        for target in self:
            employee = target.employee_id
            if target.scope == 'employee' and employee:
                target.team_id = employee.ff_team_id
                target.department_id = employee.department_id
                target.company_id = employee.company_id
            elif not target.company_id:
                target.company_id = self.env.company

    @api.depends('scope', 'employee_id', 'team_id.manager_id', 'department_id.manager_id')
    def _compute_owner(self):
        for target in self:
            target.owner_id = {
                'employee': target.employee_id,
                'team': target.team_id.manager_id,
                'department': target.department_id.manager_id,
            }.get(target.scope, self.env['hr.employee'])

    def _ff_members(self):
        """The employees whose work counts towards this target."""
        self.ensure_one()
        Employee = self.env['hr.employee'].sudo()
        if self.scope == 'company':
            return Employee.search([('company_id', '=', self.company_id.id)])
        if self.scope == 'department':
            return Employee.search([('department_id', 'child_of', self.department_id.ids)]) if self.department_id else Employee
        if self.scope == 'team':
            return Employee.search([('ff_team_id', 'child_of', self.team_id.ids)]) if self.team_id else Employee
        if not self.employee_id:
            return Employee
        # Someone who has split their target down counts their people's work too.
        if self.child_ids:
            return Employee.search([('id', 'child_of', self.employee_id.ids)])
        return self.employee_id.sudo()

    # ------------------------------------------------------------------
    # Rules
    # ------------------------------------------------------------------
    @api.model_create_multi
    def create(self, vals_list):
        default_rule = target_param(self.env, 'default_rule_id', False)
        for vals in vals_list:
            if vals.get('month'):
                vals['month'] = fields.Date.to_date(vals['month']).replace(day=1)
            if default_rule and not vals.get('parent_id') and 'incentive_rule_id' not in vals:
                vals['incentive_rule_id'] = int(default_rule)
        return super().create(vals_list)

    def write(self, vals):
        if vals.get('month'):
            vals['month'] = fields.Date.to_date(vals['month']).replace(day=1)
        return super().write(vals)

    @api.constrains('scope', 'employee_id', 'team_id', 'department_id')
    def _check_subject(self):
        needed = {'employee': 'employee_id', 'team': 'team_id', 'department': 'department_id'}
        for target in self:
            field = needed.get(target.scope)
            if field and not target[field]:
                raise ValidationError(self.env._('Choose the %s this target is for.', dict(SCOPES)[target.scope].lower()))

    @api.constrains('scope', 'employee_id', 'team_id', 'department_id', 'company_id', 'month')
    def _check_unique(self):
        for target in self:
            clash = self.search_count([
                ('id', '!=', target.id), ('month', '=', target.month), ('scope', '=', target.scope),
                ('employee_id', '=', target.employee_id.id), ('team_id', '=', target.team_id.id)
                if target.scope == 'team' else ('id', '!=', 0),
                ('department_id', '=', target.department_id.id) if target.scope == 'department' else ('id', '!=', 0),
                ('company_id', '=', target.company_id.id),
            ])
            if clash:
                raise ValidationError(self.env._('%s already has a target for that month.', target.name))

    @api.constrains(*TARGET_FIELDS)
    def _check_positive(self):
        for target in self:
            if min(target[field] for field in TARGET_FIELDS) < 0:
                raise ValidationError(self.env._('Targets cannot be negative.'))

    @api.constrains('parent_id', *TARGET_FIELDS)
    def _check_split(self):
        """Children may not add up to more than their parent (unless the setting allows it)."""
        if target_param(self.env, 'split_mode', 'not_above') == 'free':
            return
        for parent in (self.mapped('parent_id') | self.filtered('child_ids')):
            for _key, field, label, money in METRICS:
                given = sum(parent.child_ids.mapped(field))
                if parent[field] and given > parent[field] + 0.001:
                    raise ValidationError(self.env._(
                        '%(label)s split among %(parent)s comes to %(given)s, more than its target of %(target)s.',
                        label=label, parent=parent.name, given=given, target=parent[field]))

    @api.depends('child_ids', *TARGET_FIELDS, *['child_ids.%s' % f for f in TARGET_FIELDS])
    def _compute_unallocated(self):
        for target in self:
            if not target.child_ids:
                target.unallocated = False
                continue
            left = []
            for _key, field, label, money in METRICS:
                rest = target[field] - sum(target.child_ids.mapped(field))
                if target[field] and rest > 0.001:
                    left.append('%s %s' % (label, '{:,.0f}'.format(rest)))
            target.unallocated = ', '.join(left) or self.env._('Fully split')

    # ------------------------------------------------------------------
    # What was done
    # ------------------------------------------------------------------
    def _compute_actuals(self):
        for target in self:
            if not target.month:
                target.update({'visit_actual': 0, 'customer_actual': 0, 'sales_actual': 0.0,
                               'collection_actual': 0.0, 'achievement': 0})
                continue
            actual = target._ff_actual()
            target.update({
                'visit_actual': actual['visits'],
                'customer_actual': actual['customers'],
                'sales_actual': actual['sales'],
                'collection_actual': actual['collections'],
                'achievement': target._ff_achievement(actual),
            })

    def _ff_actual(self):
        self.ensure_one()
        start, end = month_bounds(self.month)
        members = self._ff_members()
        total = {'visits': 0, 'customers': 0, 'sales': 0.0, 'collections': 0.0}
        for row in self.ff_actuals(members, start, end).values():
            for key in total:
                total[key] += row[key]
        return total

    def _ff_achievement(self, actual):
        self.ensure_one()
        scores = [min(percent(actual[metric], self[field]), 100) for metric, field, _label, _money in METRICS
                  if self[field]]
        return round(sum(scores) / len(scores)) if scores else 0

    def _ff_metric_percents(self, actual):
        return {metric: percent(actual[metric], self[field]) for metric, field, _l, _m in METRICS if self[field]}

    @api.depends('incentive_rule_id')
    def _compute_incentive(self):
        for target in self:
            rule = target.incentive_rule_id
            if not rule or not target.month:
                target.incentive_earned = 0.0
                target.incentive_status = False
                continue
            actual = target._ff_actual()
            amount, status = rule.ff_evaluate(target, actual)
            target.incentive_earned = amount
            target.incentive_status = status

    @api.model
    def _order_flow(self):
        return self.env['ir.config_parameter'].sudo().get_param('ff_base.order_flow') or 'direct'

    @api.model
    def ff_actuals(self, employees, start, end):
        """employee id -> {visits, customers, sales, collections} between local dates start..end."""
        result = {employee.id: {'visits': 0, 'customers': 0, 'sales': 0.0, 'collections': 0.0}
                  for employee in employees}
        demand = self._order_flow() == 'demand' and 'ff.demand' in self.env
        env = self.env
        for employee in employees.sudo():
            low = employee._ff_day_bounds(start)[0]
            high = employee._ff_day_bounds(end)[1]
            row = result[employee.id]
            row['visits'] = env['ff.visit'].sudo().search_count([
                ('employee_id', '=', employee.id), ('check_in_at', '>=', low), ('check_in_at', '<', high)])
            row['customers'] = env['res.partner'].sudo().with_context(active_test=False).search_count([
                ('ff_created_by_employee_id', '=', employee.id), ('create_date', '>=', low),
                ('create_date', '<', high)])
            if demand:
                row['sales'] = round(sum(env['ff.demand'].sudo().search([
                    ('employee_id', '=', employee.id), ('date', '>=', low), ('date', '<', high),
                    ('state', '!=', 'cancelled')]).mapped('amount_total')), 2)
            else:
                row['sales'] = round(sum(env['sale.order'].sudo().search([
                    ('ff_employee_id', '=', employee.id), ('date_order', '>=', low), ('date_order', '<', high),
                    ('state', '!=', 'cancel')]).mapped('amount_total')), 2)
            if 'ff.collection' in env:
                row['collections'] = round(sum(env['ff.collection'].sudo().search([
                    ('employee_id', '=', employee.id), ('date', '>=', low), ('date', '<', high),
                    ('state', '!=', 'cancelled')]).mapped('amount')), 2)
        return result

    def ff_row(self):
        """One target as the app and the panel show it."""
        self.ensure_one()
        actual = self._ff_actual()
        amount, status = self.incentive_rule_id.ff_evaluate(self, actual) if self.incentive_rule_id else (0.0, None)
        return {
            'id': self.id,
            'name': self.name,
            'scope': self.scope,
            'employee_id': self.employee_id.id or None,
            'employee': self.employee_id.name or self.team_id.name or self.department_id.name or self.company_id.name,
            'owner': {'id': self.owner_id.id, 'name': self.owner_id.name} if self.owner_id else None,
            'parent_id': self.parent_id.id or None,
            'children': len(self.child_ids),
            'metrics': [{
                'key': metric, 'label': label, 'money': money,
                'target': self[field], 'actual': actual[metric], 'percent': percent(actual[metric], self[field]),
                'allocated': sum(self.child_ids.mapped(field)),
            } for metric, field, label, money in METRICS if self[field]],
            'achievement': self._ff_achievement(actual),
            'incentive': {'rule': self.incentive_rule_id.name, 'earned': amount, 'status': status}
            if self.incentive_rule_id else None,
        }

    @api.model
    def ff_progress(self, employees, day):
        """Employee targets for the month containing ``day``, one row per employee with a target."""
        start, end = month_bounds(day)
        targets = self.sudo().search([
            ('scope', '=', 'employee'), ('employee_id', 'in', employees.ids), ('month', '=', start)])
        rows = [target.ff_row() for target in targets.sorted(lambda t: t.employee_id.name or '')]
        return {'month': start.isoformat(), 'start': start, 'end': end, 'rows': rows}

    # ------------------------------------------------------------------
    # Splitting
    # ------------------------------------------------------------------
    def ff_can_split(self, employee):
        """The owner of a target may split it; so may anyone above the owner, and target admins."""
        self.ensure_one()
        if target_param(self.env, 'who_splits', 'managers') == 'office':
            return False
        owner = self.owner_id
        return bool(owner) and (owner == employee or owner in employee._ff_subordinates())

    @api.model
    def ff_split_options(self, employee, parent):
        """Where a target may go next: sub-teams, members of the team, people reporting to the owner."""
        Employee = self.env['hr.employee'].sudo()
        choices = []
        if parent.scope == 'company':
            for department in self.env['hr.department'].sudo().search([('company_id', 'in', (False, parent.company_id.id))]):
                choices.append(('department', department))
            for team in self.env['ff.team'].sudo().search([('parent_id', '=', False), ('company_id', '=', parent.company_id.id)]):
                choices.append(('team', team))
        elif parent.scope == 'department':
            for team in self.env['ff.team'].sudo().search([('member_ids.department_id', 'child_of', parent.department_id.ids)]):
                choices.append(('team', team))
            for person in Employee.search([('department_id', '=', parent.department_id.id)]):
                choices.append(('employee', person))
        elif parent.scope == 'team':
            for team in parent.team_id.child_ids:
                choices.append(('team', team))
            for person in parent.team_id.member_ids:
                choices.append(('employee', person))
        else:
            for person in Employee.search([('parent_id', '=', parent.employee_id.id)]):
                choices.append(('employee', person))
        return choices

    def ff_split(self, employee, allocations):
        """Create or update the targets under this one. ``allocations``: [{scope, id, visits, customers, sales, collections}]."""
        self.ensure_one()
        if employee and not self.ff_can_split(employee):
            raise UserError(self.env._('You cannot split this target.'))
        allowed = {(scope, record.id) for scope, record in self.ff_split_options(employee, self)}
        field_of = {'employee': 'employee_id', 'team': 'team_id', 'department': 'department_id'}
        Target = self.sudo()
        touched = Target.browse()
        for row in allocations:
            scope, record_id = row.get('scope'), int(row.get('id') or 0)
            if (scope, record_id) not in allowed:
                raise UserError(self.env._('That person or team is not under this target.'))
            values = {
                'visit_target': int(row.get('visits') or 0),
                'customer_target': int(row.get('customers') or 0),
                'sales_target': float(row.get('sales') or 0),
                'collection_target': float(row.get('collections') or 0),
            }
            existing = Target.search([('parent_id', '=', self.id), ('scope', '=', scope),
                                      (field_of[scope], '=', record_id)], limit=1)
            if existing:
                existing.write(values)
                touched |= existing
            else:
                # Taking over a target already set on its own for the same month.
                loose = Target.search([('parent_id', '=', False), ('scope', '=', scope), ('month', '=', self.month),
                                       (field_of[scope], '=', record_id)], limit=1)
                if loose:
                    loose.write(dict(values, parent_id=self.id))
                    touched |= loose
                else:
                    touched |= Target.create(dict(values, scope=scope, month=self.month, parent_id=self.id,
                                                  company_id=self.company_id.id, assigned_by_id=employee.id if employee else False,
                                                  incentive_rule_id=self.incentive_rule_id.id,
                                                  **{field_of[scope]: record_id}))
        for target in touched:
            if target.owner_id and 'ff.notification' in self.env:
                self.env['ff.notification'].sudo().ff_push(
                    self.env._('New target'), self.env._('%s set for %s.', target.name, target.month.strftime('%B')),
                    employee=target.owner_id, record=target)
        return touched

    # ------------------------------------------------------------------
    # Office conveniences
    # ------------------------------------------------------------------
    def action_copy_to_next_month(self):
        """Carry the selected targets into the following month, skipping any already set."""
        created = self.browse()
        for target in self:
            month = target.month + relativedelta(months=1)
            same = [('month', '=', month), ('scope', '=', target.scope), ('employee_id', '=', target.employee_id.id),
                    ('team_id', '=', target.team_id.id), ('department_id', '=', target.department_id.id)]
            if self.search_count(same):
                continue
            created |= target.copy({'month': month})
        return {
            'type': 'ir.actions.act_window',
            'name': self.env._('Copied Targets'),
            'res_model': 'ff.target',
            'view_mode': 'list,form',
            'domain': [('id', 'in', created.ids)],
        }

    def action_open_split(self):
        self.ensure_one()
        return {
            'type': 'ir.actions.act_window', 'name': self.env._('Split %s', self.name), 'res_model': 'ff.target',
            'view_mode': 'list,form', 'domain': [('parent_id', '=', self.id)],
            'context': {'default_parent_id': self.id, 'default_month': self.month,
                        'default_company_id': self.company_id.id, 'default_incentive_rule_id': self.incentive_rule_id.id,
                        'default_scope': 'employee' if self.scope == 'employee' else 'team'},
        }

    @api.model
    def ff_leaderboard(self, employees, day, limit=10):
        """Employees ranked by achievement, then sales - for the month containing ``day``."""
        rows = self.ff_progress(employees, day)['rows']
        if not rows:
            # Nobody has a target: rank on what they did.
            start, end = month_bounds(day)
            actuals = self.ff_actuals(employees, start, end)
            names = {e.id: e.name for e in employees}
            rows = [{'employee_id': eid, 'employee': names[eid], 'achievement': None,
                     'metrics': [{'key': k, 'label': l, 'money': m, 'actual': a[k], 'target': 0, 'percent': 0}
                                 for k, _f, l, m in METRICS]} for eid, a in actuals.items()]

        def sales(row):
            return next((m['actual'] for m in row['metrics'] if m['key'] == 'sales'), 0)

        rows.sort(key=lambda row: (-(row['achievement'] or 0), -sales(row)))
        for rank, row in enumerate(rows, 1):
            row['rank'] = rank
        return rows[:limit]


class FfIncentiveRule(models.Model):
    _name = 'ff.incentive.rule'
    _description = 'Target Incentive Rule'
    _order = 'sequence, name'

    name = fields.Char(required=True)
    sequence = fields.Integer(default=10)
    active = fields.Boolean(default=True)
    company_id = fields.Many2one('res.company', default=lambda self: self.env.company)
    currency_id = fields.Many2one(related='company_id.currency_id')
    condition = fields.Selection([
        ('all', 'Every target must be reached'),
        ('each', 'Each target reached pays its own amount'),
        ('pro_rata', 'Pay in proportion to what was achieved'),
    ], required=True, default='all',
        help='Every target: nothing is paid until all the targets set are reached.\n'
             'Each target: every target reached pays its amount, the others pay nothing.\n'
             'In proportion: each target pays its amount times the achieved share, once past the threshold.')
    threshold_pct = fields.Integer(string='Counts As Reached At (%)', default=100,
                                   help='90 pays a target reached to 90% as if it were reached.')
    cap_pct = fields.Integer(string='Pay Up To (%)', default=100,
                             help='In proportion: the most a target can count for, e.g. 120 pays extra for beating it.')
    amount = fields.Monetary(string='Amount When All Reached', help='Used by "Every target must be reached".')
    visit_amount = fields.Monetary(string='Visits')
    customer_amount = fields.Monetary(string='New Customers')
    sales_amount = fields.Monetary(string='Sales')
    collection_amount = fields.Monetary(string='Collections')
    sales_commission_pct = fields.Float(string='Plus % of Sales', digits=(5, 2),
                                        help='Added on top once the rule pays anything.')
    note = fields.Text()

    def ff_evaluate(self, target, actual):
        """(amount earned, a line saying why)."""
        self.ensure_one()
        percents = target._ff_metric_percents(actual)
        if not percents:
            return 0.0, 'No targets set'
        amounts = {'visits': self.visit_amount, 'customers': self.customer_amount,
                   'sales': self.sales_amount, 'collections': self.collection_amount}
        reached = {key: pct >= self.threshold_pct for key, pct in percents.items()}
        earned = 0.0
        if self.condition == 'all':
            missing = [key for key, ok in reached.items() if not ok]
            if missing:
                return 0.0, '%d of %d targets reached' % (len(reached) - len(missing), len(reached))
            earned = self.amount
            status = 'All targets reached'
        elif self.condition == 'each':
            earned = sum(amounts[key] for key, ok in reached.items() if ok)
            status = '%d of %d targets reached' % (sum(reached.values()), len(reached))
        else:
            for key, pct in percents.items():
                if pct >= self.threshold_pct:
                    earned += amounts[key] * min(pct, self.cap_pct) / 100.0
            status = 'Paid on achievement'
        if earned and self.sales_commission_pct:
            earned += actual['sales'] * self.sales_commission_pct / 100.0
        return round(earned, 2), status
