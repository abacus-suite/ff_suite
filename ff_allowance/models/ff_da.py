from datetime import timedelta

from odoo import api, fields, models
from odoo.exceptions import UserError


class FfDaRate(models.Model):
    """Daily allowance per designation: inside the person's primary territory, and outside it."""
    _name = 'ff.da.rate'
    _description = 'Daily Allowance Rate'
    _order = 'designation_id'

    designation_id = fields.Many2one('ff.designation', string='Designation', required=True, index=True)
    primary_rate = fields.Monetary(string='Primary Territory', help='Paid for a working day spent in the '
                                   'primary territory.')
    primary_na = fields.Boolean(string='Primary: not applicable',
                                help='Nothing is paid for a day in the primary territory (works from home).')
    outside_rate = fields.Monetary(string='Outside Territory', required=True)
    company_id = fields.Many2one('res.company', required=True, default=lambda self: self.env.company)
    currency_id = fields.Many2one(related='company_id.currency_id')
    active = fields.Boolean(default=True)

    _designation_uniq = models.Constraint('UNIQUE(designation_id, company_id)',
                                          'A rate is already set for this designation.')

    @api.model
    def _ff_seed_defaults(self):
        """Add the client's table (DA by designation, TA Rs 4 per km, OLA) where nothing is set yet."""
        env = self.env
        Designation = env['ff.designation'].sudo()

        def designation(name, level, ref=None):
            if ref:
                found = env.ref(ref, raise_if_not_found=False)
                if found:
                    return found
            return Designation.search([('name', '=ilike', name)], limit=1) or                 Designation.create({'name': name, 'level': level})

        officer = designation('Sales Officer', 1, 'ff_base.designation_sales_officer')
        manager = designation('Sales Manager', 2)
        operations = designation('Sales Operation Manager', 3)
        table = [
            (operations, 0.0, True, 350.0),
            (officer, 100.0, False, 200.0),
            (manager, 100.0, False, 300.0),
        ]
        for des, primary, primary_na, outside in table:
            if not self.sudo().search_count([('designation_id', '=', des.id)]):
                self.sudo().create({'designation_id': des.id, 'primary_rate': primary, 'primary_na': primary_na,
                                    'outside_rate': outside})
        Travel = env['ff.travel.rate'].sudo()
        if not Travel.search_count([]):
            Travel.create({'scope': 'all', 'assigned_rate': 4.0, 'other_rate': 4.0})
        params = env['ir.config_parameter'].sudo()
        for key, value in (('ff_allowance.ola_monthly', '1000'), ('ff_allowance.ola_days', '26'),
                           ('ff_allowance.ola_half_hours', '4'), ('ff_allowance.ola_full_hours', '8')):
            if not params.get_param(key):
                params.set_param(key, value)
        return True

    @api.model
    def _ff_for_employee(self, employee):
        employee = employee.sudo()
        if not employee.ff_designation_id:
            return self.browse()
        return self.sudo().search([('designation_id', '=', employee.ff_designation_id.id),
                                   ('company_id', 'in', (False, employee.company_id.id))], limit=1)


class FfDaClaim(models.Model):
    """One working day's daily allowance, worked out from where the person visited.

    A day is paid at the outside rate when any outlet or distributor visited is outside the person's primary
    territory, otherwise at the primary rate. A day without a visit pays no DA.
    """
    _name = 'ff.da.claim'
    _description = 'Daily Allowance'
    _order = 'date desc, employee_id'

    employee_id = fields.Many2one('hr.employee', required=True, index=True, ondelete='cascade')
    date = fields.Date(required=True, index=True)
    week_start = fields.Date(compute='_compute_week_start', store=True, index=True)
    kind = fields.Selection([('primary', 'Primary territory'), ('outside', 'Outside territory'),
                             ('none', 'No DA')], default='none', readonly=True)
    rate = fields.Monetary(readonly=True)
    amount = fields.Monetary(readonly=True)
    visit_count = fields.Integer(readonly=True)
    outside_count = fields.Integer(readonly=True)
    detail = fields.Text(readonly=True)
    state = fields.Selection([('draft', 'Calculated'), ('submitted', 'To Approve'), ('approved', 'Approved'),
                              ('rejected', 'Rejected')], default='draft', required=True, index=True)
    approver_id = fields.Many2one('res.users', readonly=True, copy=False)
    decided_at = fields.Datetime(readonly=True, copy=False)
    company_id = fields.Many2one(related='employee_id.company_id', store=True)
    currency_id = fields.Many2one(related='company_id.currency_id')

    _employee_date_uniq = models.Constraint('UNIQUE(employee_id, date)', 'One DA per employee and day.')

    @api.depends('date')
    def _compute_week_start(self):
        for rec in self:
            rec.week_start = rec.date - timedelta(days=rec.date.weekday()) if rec.date else False

    # ------------------------------------------------------------------
    @api.model
    def _ff_primary_places(self, employee):
        """The territories (or, without any, the cities) that count as the person's own."""
        territories = employee.ff_territory_ids if 'ff_territory_ids' in employee._fields else False
        cities = employee.ff_district_ids if 'ff_district_ids' in employee._fields else False
        return territories, cities

    @api.model
    def _ff_is_outside(self, partner, territories, cities):
        """Is this contact outside the person's primary territory?"""
        if not territories and not cities:
            return False  # nothing is set for the person: every place is their own
        territory = partner.ff_territory_id if 'ff_territory_id' in partner._fields else False
        if not territory and 'ff_beat_line_ids' in partner._fields:
            beat_territories = partner.ff_beat_line_ids.beat_id.mapped('territory_id') \
                if 'territory_id' in self.env['ff.beat']._fields else []
            territory = beat_territories[:1] if beat_territories else False
        if territory and territories:
            return territory not in territories
        district = partner.ff_district_id
        if district and cities:
            return district not in cities
        return False

    @api.model
    def _ff_compute(self, employee, day):
        """Create or refresh the DA of ``employee`` for ``day``; a settled one is left alone."""
        employee = employee.sudo()
        rate = self.env['ff.da.rate']._ff_for_employee(employee)
        if not rate:
            return self.browse()
        claim = self.sudo().search([('employee_id', '=', employee.id), ('date', '=', day)], limit=1)
        if claim and claim.state in ('approved', 'rejected'):
            return claim
        start, end = employee._ff_day_bounds(day)
        visits = self.env['ff.visit'].sudo().search([
            ('employee_id', '=', employee.id), ('check_in_at', '>=', start), ('check_in_at', '<', end)])
        territories, cities = self._ff_primary_places(employee)
        counted = visits.filtered(lambda v: v.partner_id.ff_category_type in ('outlet', 'distributor', 'customer'))
        vehicle, owner = employee._ff_day_vehicle(day)
        if vehicle == 'two_wheeler' and owner == 'own':
            counted = visits.browse()  # an own scooter is paid as TA by the meter, not as DA
        outside = counted.filtered(lambda v: self._ff_is_outside(v.partner_id, territories, cities))
        if not counted:
            kind, amount_rate = 'none', 0.0
        elif outside:
            kind, amount_rate = 'outside', rate.outside_rate
        else:
            kind, amount_rate = 'primary', 0.0 if rate.primary_na else rate.primary_rate
        lines = []
        for visit in counted:
            lines.append('%s%s' % (visit.partner_id.name, ' (outside)' if visit in outside else ''))
        vals = {
            'kind': kind, 'rate': amount_rate, 'amount': amount_rate,
            'visit_count': len(counted), 'outside_count': len(outside), 'detail': '\n'.join(lines),
        }
        if claim:
            claim.write(vals)
        else:
            if kind == 'none':
                return claim
            claim = self.sudo().create(dict(vals, employee_id=employee.id, date=day))
        return claim

    @api.model
    def _cron_compute(self):
        """Work out the last days, and send every finished week to the manager."""
        today = fields.Date.context_today(self)
        since = fields.Datetime.to_datetime(today - timedelta(days=9))
        employees = self.env['ff.visit'].sudo().search([('check_in_at', '>=', since)]).employee_id
        for employee in employees:
            local_today = employee._ff_today()
            for back in range(0, 9):
                self._ff_compute(employee, local_today - timedelta(days=back))
        monday = today - timedelta(days=today.weekday())
        done = self.sudo().search([('state', '=', 'draft'), ('week_start', '<', monday), ('amount', '>', 0)])
        done.write({'state': 'submitted'})
        if 'ff.notification' in self.env:
            for emp in done.mapped('employee_id'):
                manager_emp = emp.parent_id
                if manager_emp:
                    emp_claims = done.filtered(lambda c: c.employee_id == emp)
                    total = sum(emp_claims.mapped('amount'))
                    symbol = emp_claims[:1].currency_id.symbol or '₹'
                    self.env['ff.notification'].sudo().ff_push(
                        title=self.env._('DA to Approve'),
                        body=self.env._('%(employee)s DA submitted for week %(week)s (%(symbol)s%(total).2f)',
                                        employee=emp.name,
                                        week=emp_claims[:1].week_start or '',
                                        symbol=symbol,
                                        total=total),
                        kind='approval',
                        employee=manager_emp,
                        record=emp_claims[:1],
                    )

    # ------------------------------------------------------------------
    def ff_decide_week(self, manager, approve):
        """The manager settles every submitted day of the employee's week at once."""
        for claim in self:
            if claim.employee_id not in manager._ff_subordinates():
                raise UserError(self.env._('That person is not in your team.'))
        submitted = self.filtered(lambda c: c.state == 'submitted')
        submitted.write({
            'state': 'approved' if approve else 'rejected',
            'approver_id': manager.user_id.id or False, 'decided_at': fields.Datetime.now()})
        if 'ff.notification' in self.env:
            for emp in submitted.mapped('employee_id'):
                claims = submitted.filtered(lambda c: c.employee_id == emp)
                total = sum(claims.mapped('amount'))
                symbol = claims[:1].currency_id.symbol or '₹'
                title = self.env._('Daily Allowance Approved') if approve else self.env._('Daily Allowance Rejected')
                body = self.env._('Your Daily Allowance for week %(week)s (%(symbol)s%(total).2f) was %(status)s by %(manager)s.',
                                  week=claims[:1].week_start or '',
                                  symbol=symbol,
                                  total=total,
                                  status=self.env._('approved') if approve else self.env._('rejected'),
                                  manager=manager.name)
                self.env['ff.notification'].sudo().ff_push(
                    title=title, body=body, kind='decision',
                    employee=emp, record=claims[:1]
                )
