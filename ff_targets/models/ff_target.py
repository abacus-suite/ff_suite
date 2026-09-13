"""Monthly targets per employee, and what they actually did against them."""
import calendar

from dateutil.relativedelta import relativedelta

from odoo import api, fields, models
from odoo.exceptions import ValidationError

# metric -> (target field, label, money?)
METRICS = [
    ('visits', 'visit_target', 'Visits', False),
    ('customers', 'customer_target', 'New customers', False),
    ('sales', 'sales_target', 'Sales', True),
    ('collections', 'collection_target', 'Collections', True),
]


def month_bounds(day):
    first = day.replace(day=1)
    return first, first.replace(day=calendar.monthrange(first.year, first.month)[1])


def percent(actual, target):
    return round(actual * 100.0 / target) if target else 0


class FfTarget(models.Model):
    _name = 'ff.target'
    _description = 'Employee Monthly Target'
    _inherit = ['mail.thread']
    _order = 'month desc, employee_id'

    employee_id = fields.Many2one('hr.employee', required=True, index=True, ondelete='cascade', tracking=True)
    team_id = fields.Many2one(related='employee_id.ff_team_id', store=True)
    department_id = fields.Many2one(related='employee_id.department_id', store=True)
    month = fields.Date(required=True, index=True, tracking=True,
                        default=lambda self: fields.Date.context_today(self).replace(day=1),
                        help='Any day in the month; saved as its first day.')
    company_id = fields.Many2one(related='employee_id.company_id', store=True)
    currency_id = fields.Many2one(related='company_id.currency_id')

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

    _employee_month_uniq = models.Constraint('UNIQUE(employee_id, month)',
                                             'This employee already has a target for that month.')

    @api.depends('employee_id', 'month')
    def _compute_display_name(self):
        for target in self:
            target.display_name = '%s - %s' % (target.employee_id.name or '',
                                               target.month.strftime('%b %Y') if target.month else '')

    @api.model_create_multi
    def create(self, vals_list):
        for vals in vals_list:
            if vals.get('month'):
                vals['month'] = fields.Date.to_date(vals['month']).replace(day=1)
        return super().create(vals_list)

    def write(self, vals):
        if vals.get('month'):
            vals['month'] = fields.Date.to_date(vals['month']).replace(day=1)
        return super().write(vals)

    @api.constrains('visit_target', 'customer_target', 'sales_target', 'collection_target')
    def _check_positive(self):
        for target in self:
            if min(target.visit_target, target.customer_target, target.sales_target, target.collection_target) < 0:
                raise ValidationError(self.env._('Targets cannot be negative.'))

    def _compute_actuals(self):
        for target in self:
            if not target.employee_id or not target.month:
                target.update({'visit_actual': 0, 'customer_actual': 0, 'sales_actual': 0.0,
                               'collection_actual': 0.0, 'achievement': 0})
                continue
            start, end = month_bounds(target.month)
            actual = self.ff_actuals(target.employee_id, start, end)[target.employee_id.id]
            target.update({
                'visit_actual': actual['visits'],
                'customer_actual': actual['customers'],
                'sales_actual': actual['sales'],
                'collection_actual': actual['collections'],
                'achievement': target._ff_achievement(actual),
            })

    def _ff_achievement(self, actual):
        self.ensure_one()
        scores = [min(percent(actual[metric], self[field]), 100) for metric, field, _label, _money in METRICS
                  if self[field]]
        return round(sum(scores) / len(scores)) if scores else 0

    # ------------------------------------------------------------------
    # What was done
    # ------------------------------------------------------------------
    @api.model
    def _order_flow(self):
        return self.env['ir.config_parameter'].sudo().get_param('ff_base.order_flow') or 'direct'

    @api.model
    def ff_actuals(self, employees, start, end):
        """employee id -> {visits, customers, sales, collections} between local dates start..end."""
        result = {employee.id: {'visits': 0, 'customers': 0, 'sales': 0.0, 'collections': 0.0}
                  for employee in employees}
        demand = self._order_flow() == 'demand' and 'ff.demand' in self.env
        for employee in employees.sudo():
            low = employee._ff_day_bounds(start)[0]
            high = employee._ff_day_bounds(end)[1]
            row = result[employee.id]
            row['visits'] = self.env['ff.visit'].sudo().search_count([
                ('employee_id', '=', employee.id), ('check_in_at', '>=', low), ('check_in_at', '<', high)])
            row['customers'] = self.env['res.partner'].sudo().with_context(active_test=False).search_count([
                ('ff_created_by_employee_id', '=', employee.id), ('create_date', '>=', low),
                ('create_date', '<', high)])
            if demand:
                demands = self.env['ff.demand'].sudo().search([
                    ('employee_id', '=', employee.id), ('date', '>=', low), ('date', '<', high),
                    ('state', '!=', 'cancelled')])
                row['sales'] = round(sum(demands.mapped('amount_total')), 2)
            else:
                orders = self.env['sale.order'].sudo().search([
                    ('ff_employee_id', '=', employee.id), ('date_order', '>=', low), ('date_order', '<', high),
                    ('state', '!=', 'cancel')])
                row['sales'] = round(sum(orders.mapped('amount_total')), 2)
            if 'ff.collection' in self.env:
                collections = self.env['ff.collection'].sudo().search([
                    ('employee_id', '=', employee.id), ('date', '>=', low), ('date', '<', high),
                    ('state', '!=', 'cancelled')])
                row['collections'] = round(sum(collections.mapped('amount')), 2)
        return result

    @api.model
    def ff_progress(self, employees, day):
        """Targets and achievement for the month containing ``day``, one row per employee with a target."""
        start, end = month_bounds(day)
        targets = self.sudo().search([('employee_id', 'in', employees.ids), ('month', '=', start)])
        actuals = self.ff_actuals(targets.mapped('employee_id'), start, end)
        rows = []
        for target in targets.sorted(lambda t: t.employee_id.name or ''):
            actual = actuals[target.employee_id.id]
            metrics = [{
                'key': metric, 'label': label, 'money': money,
                'target': target[field], 'actual': actual[metric], 'percent': percent(actual[metric], target[field]),
            } for metric, field, label, money in METRICS if target[field]]
            rows.append({
                'id': target.id,
                'employee_id': target.employee_id.id,
                'employee': target.employee_id.name,
                'metrics': metrics,
                'achievement': target._ff_achievement(actual),
            })
        return {'month': start.isoformat(), 'start': start, 'end': end, 'rows': rows}

    # ------------------------------------------------------------------
    # Office conveniences
    # ------------------------------------------------------------------
    def action_copy_to_next_month(self):
        """Carry the selected targets into the following month, skipping any already set."""
        Target = self.env['ff.target']
        created = Target
        for target in self:
            month = target.month + relativedelta(months=1)
            if Target.search_count([('employee_id', '=', target.employee_id.id), ('month', '=', month)]):
                continue
            created |= target.copy({'month': month})
        return {
            'type': 'ir.actions.act_window',
            'name': self.env._('Copied Targets'),
            'res_model': 'ff.target',
            'view_mode': 'list,form',
            'domain': [('id', 'in', created.ids)],
        }
