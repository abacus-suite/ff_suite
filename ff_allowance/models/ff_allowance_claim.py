from datetime import timedelta

from odoo import api, fields, models
from odoo.exceptions import AccessError, UserError

from odoo.addons.ff_base.tools import haversine_m

from .ff_allowance_policy import BASES


def _visit_point(visit):
    partner = visit.partner_id
    if partner.partner_latitude or partner.partner_longitude:
        return partner.partner_latitude, partner.partner_longitude
    return visit.check_in_lat, visit.check_in_lng


def _straight_km(a, b, factor):
    if not a or not b or not all(a) or not all(b):
        return 0.0
    return round(haversine_m(a[0], a[1], b[0], b[1]) / 1000.0 * factor, 2)


class FfAllowanceClaim(models.Model):
    _name = 'ff.allowance.claim'
    _description = 'Daily Travel Allowance'
    _inherit = ['mail.thread', 'mail.activity.mixin', 'ff.numbered.mixin']
    _ff_sequence_code = 'ff.allowance.claim'
    _order = 'date desc, employee_id'

    employee_id = fields.Many2one('hr.employee', required=True, index=True, ondelete='cascade')
    team_id = fields.Many2one(related='employee_id.ff_team_id', store=True)
    department_id = fields.Many2one(related='employee_id.department_id', store=True)
    date = fields.Date(required=True, index=True)
    policy_id = fields.Many2one('ff.allowance.policy', readonly=True)
    basis = fields.Selection(BASES, readonly=True)
    vehicle_type = fields.Selection(related='policy_id.vehicle_type')
    company_id = fields.Many2one(related='employee_id.company_id', store=True)
    currency_id = fields.Many2one(related='company_id.currency_id')
    distance_km = fields.Float(string='Distance (km)', digits=(10, 2), readonly=True)
    rate_per_km = fields.Monetary(readonly=True)
    amount = fields.Monetary(readonly=True, tracking=True)
    visit_count = fields.Integer(readonly=True)
    estimated = fields.Boolean(readonly=True, help='Some legs were estimated from straight-line distance.')
    line_ids = fields.One2many('ff.allowance.claim.line', 'claim_id', string='Legs', readonly=True)
    state = fields.Selection([
        ('draft', 'Draft'),
        ('submitted', 'To Approve'),
        ('approved', 'Approved'),
        ('rejected', 'Rejected'),
    ], default='draft', required=True, tracking=True, index=True)
    note = fields.Text()
    approver_id = fields.Many2one('res.users', readonly=True, copy=False)
    decided_at = fields.Datetime(readonly=True, copy=False)

    _employee_date_uniq = models.Constraint('UNIQUE(employee_id, date)', 'One allowance per employee and day.')

    @api.depends('employee_id', 'date')
    def _compute_display_name(self):
        for claim in self:
            claim.display_name = '%s - %s' % (claim.employee_id.name or '', claim.date or '')

    # ------------------------------------------------------------------
    # Computation
    # ------------------------------------------------------------------
    @api.model
    def _ff_compute(self, employee, day):
        """Create / refresh the draft allowance of ``employee`` for ``day``."""
        employee = employee.sudo()
        Claim = self.sudo()
        claim = Claim.search([('employee_id', '=', employee.id), ('date', '=', day)], limit=1)
        if claim and claim.state != 'draft':
            return claim
        policy = self.env['ff.allowance.policy']._ff_for_employee(employee)
        start, end = employee._ff_day_bounds(day)
        visits = self.env['ff.visit'].sudo().search([
            ('employee_id', '=', employee.id), ('check_in_at', '>=', start), ('check_in_at', '<', end),
        ], order='check_in_at asc')
        attendances = self.env['hr.attendance'].sudo().search([
            ('employee_id', '=', employee.id), ('check_in', '>=', start), ('check_in', '<', end),
        ], order='check_in asc')
        if not policy or not (visits or attendances):
            return claim

        legs = getattr(self, '_ff_legs_%s' % policy.basis)(policy, employee, day, visits, attendances)
        km = round(sum(leg['distance_km'] for leg in legs), 2)
        if policy.max_km_per_day:
            km = min(km, policy.max_km_per_day)
        amount = policy.fixed_amount if policy.basis == 'fixed' else km * policy.rate_per_km
        vals = {
            'policy_id': policy.id,
            'basis': policy.basis,
            'distance_km': km,
            'rate_per_km': 0.0 if policy.basis == 'fixed' else policy.rate_per_km,
            'amount': policy.currency_id.round(amount),
            'visit_count': len(visits),
            'estimated': any(leg.get('estimated') for leg in legs),
            'line_ids': [(5, 0, 0)] + [(0, 0, dict(leg, sequence=i)) for i, leg in enumerate(legs, start=1)],
        }
        if claim:
            claim.write(vals)
        else:
            claim = Claim.create(dict(vals, employee_id=employee.id, date=day))
        return claim

    def _ff_legs_gps(self, policy, employee, day, visits, attendances):
        track = self.env['ff.daily.track']._ff_compute(employee, day)
        return [{'name': self.env._('GPS tracked distance'), 'distance_km': track.distance_km if track else 0.0}]

    def _ff_legs_fixed(self, policy, employee, day, visits, attendances):
        return [{'name': self.env._('Fixed daily allowance'), 'distance_km': 0.0}]

    def _ff_legs_client(self, policy, employee, day, visits, attendances):
        """Punch-in -> each visited client in order -> punch-out."""
        stops = []
        first_in = attendances[:1]
        if first_in and (first_in.in_latitude or first_in.in_longitude):
            stops.append((self.env._('Punch-in'), (first_in.in_latitude, first_in.in_longitude)))
        for visit in visits:
            if stops and stops[-1][0] == visit.partner_id.name:
                continue  # repeated visit to the same client
            stops.append((visit.partner_id.name, _visit_point(visit)))
        last_out = attendances.filtered('check_out')[-1:]
        if last_out and (last_out.out_latitude or last_out.out_longitude):
            stops.append((self.env._('Punch-out'), (last_out.out_latitude, last_out.out_longitude)))
        return [{
            'name': '%s → %s' % (stops[i][0], stops[i + 1][0]),
            'distance_km': _straight_km(stops[i][1], stops[i + 1][1], policy.road_factor),
            'estimated': True,
        } for i in range(len(stops) - 1)]

    def _ff_legs_route(self, policy, employee, day, visits, attendances):
        """Allowance km for each route worked + agreed km between consecutive routes."""
        worked = []  # [(route, first visit, last visit)]
        for visit in visits:
            route = visit.beat_plan_id.beat_id if visit.is_planned else self.env['ff.beat']
            if not route:
                route = self.env['ff.beat.line'].sudo().search([
                    ('partner_id', '=', visit.partner_id.id),
                    ('beat_id', 'in', employee.ff_route_ids.ids or visit.beat_plan_id.beat_id.ids),
                ], limit=1).beat_id
            if not route:
                continue
            if worked and worked[-1][0] == route:
                worked[-1] = (route, worked[-1][1], visit)
            else:
                worked.append((route, visit, visit))
        if not worked:
            plan = self.env['ff.beat.plan'].sudo().search([('employee_id', '=', employee.id), ('date', '=', day)], limit=1)
            if plan and attendances:
                worked.append((plan.beat_id, None, None))

        Distance = self.env['ff.route.distance']
        legs = []
        for index, (route, first_visit, _last_visit) in enumerate(worked):
            if index:
                previous, _first, previous_last = worked[index - 1]
                agreed = Distance.ff_lookup(previous, route)
                if agreed is not None:
                    legs.append({'name': '%s → %s' % (previous.name, route.name), 'distance_km': agreed})
                else:
                    legs.append({
                        'name': '%s → %s (estimated)' % (previous.name, route.name),
                        'distance_km': _straight_km(_visit_point(previous_last), _visit_point(first_visit), policy.road_factor),
                        'estimated': True,
                    })
            if route.allowance_km:
                legs.append({'name': self.env._('Working on %s', route.display_name), 'distance_km': route.allowance_km})
        return legs

    def action_recompute(self):
        for claim in self.filtered(lambda c: c.state == 'draft'):
            self._ff_compute(claim.employee_id, claim.date)

    @api.model
    def _cron_compute(self):
        since = fields.Date.context_today(self) - timedelta(days=2)
        start = fields.Datetime.to_datetime(since)
        employees = self.env['hr.attendance'].sudo().search([('check_in', '>=', start)]).employee_id
        employees |= self.env['ff.visit'].sudo().search([('check_in_at', '>=', start)]).employee_id
        for employee in employees:
            today = employee._ff_today()
            for day in (today - timedelta(days=1), today):
                self._ff_compute(employee, day)

    # ------------------------------------------------------------------
    # Workflow
    # ------------------------------------------------------------------
    def action_submit(self):
        for claim in self.filtered(lambda c: c.state == 'draft'):
            claim.state = 'submitted'
            manager_user = claim.employee_id.parent_id.user_id
            if manager_user:
                claim.sudo().activity_schedule('mail.mail_activity_data_todo', user_id=manager_user.id,
                                               summary=self.env._('Approve travel allowance'))

    def _ff_check_approver(self):
        user = self.env.user
        if user.has_group('ff_base.group_ff_admin'):
            return
        approver = user.employee_id
        for claim in self:
            if not approver or not approver._ff_is_manager_of(claim.employee_id):
                raise AccessError(self.env._('This allowance is outside your data access.'))

    def _ff_set_decision(self, approve, approver_user=False):
        for claim in self.sudo():
            if claim.state not in ('draft', 'submitted'):
                raise UserError(self.env._('Only draft or submitted allowances can be decided.'))
            claim.write({'state': 'approved' if approve else 'rejected',
                         'approver_id': approver_user or False, 'decided_at': fields.Datetime.now()})
            if approve:
                claim._ff_assign_reference()
            claim.activity_ids.unlink()

    def action_approve(self):
        self._ff_check_approver()
        self._ff_set_decision(True, self.env.uid)

    def action_reject(self):
        self._ff_check_approver()
        self._ff_set_decision(False, self.env.uid)

    def action_reset_draft(self):
        self._ff_check_approver()
        self.sudo().filtered(lambda c: c.state == 'rejected').write({'state': 'draft'})

    def _ff_decide_as(self, employee, approve):
        """Approve or reject from the mobile app on behalf of ``employee``."""
        self.ensure_one()
        if not employee._ff_is_manager_of(self.sudo().employee_id):
            raise AccessError(self.env._('This allowance is outside your data access.'))
        self._ff_set_decision(approve, employee.user_id.id)


class FfAllowanceClaimLine(models.Model):
    _name = 'ff.allowance.claim.line'
    _description = 'Travel Allowance Leg'
    _order = 'sequence, id'

    claim_id = fields.Many2one('ff.allowance.claim', required=True, index=True, ondelete='cascade')
    sequence = fields.Integer()
    name = fields.Char(string='Leg', required=True)
    distance_km = fields.Float(string='km', digits=(10, 2))
    estimated = fields.Boolean()
