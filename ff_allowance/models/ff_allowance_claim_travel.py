import json

from odoo import fields, models
from odoo.exceptions import UserError


class FfAllowanceClaimTravel(models.Model):
    _inherit = 'ff.allowance.claim'

    basis = fields.Selection(selection_add=[('odometer', 'Odometer reading')], ondelete={'odometer': 'set null'})
    odometer_opening = fields.Float(digits=(12, 1), readonly=True)
    odometer_closing = fields.Float(digits=(12, 1), readonly=True)
    odometer_km = fields.Float(string='Odometer km', digits=(10, 1), readonly=True)
    odometer_na = fields.Boolean(string='Odometer NA', readonly=True)
    geo_km = fields.Float(string='Tracked km (GPS)', digits=(10, 1), readonly=True)
    own_km = fields.Float(string='Assigned Route km', digits=(10, 1), readonly=True)
    other_km = fields.Float(string='Other Route km', digits=(10, 1), readonly=True)
    own_rate = fields.Monetary(string='Assigned Rate', readonly=True)
    other_rate = fields.Monetary(string='Other Rate', readonly=True)
    own_amount = fields.Monetary(readonly=True)
    other_amount = fields.Monetary(readonly=True)
    split_json = fields.Text(readonly=True)

    def _ff_beat_split(self, employee, day):
        """How the day's distance divides between the employee's own routes and other routes.

        By visits on each route that day (the planned count when there are none). A day with no route at all
        counts as the employee's own.
        """
        env = self.env
        plans = env['ff.beat.plan'].sudo().search([('employee_id', '=', employee.id), ('date', '=', day)])
        own = employee.ff_route_ids
        weights = []
        for plan in plans:
            beat = plan.beat_id
            if not beat:
                continue
            visits = env['ff.visit'].sudo().search_count([('beat_plan_id', '=', plan.id)]) \
                if 'ff.visit' in env else 0
            weight = visits or getattr(plan, 'planned_count', 0) or 1
            weights.append((beat, weight, beat in own))
        total = sum(w for _b, w, _o in weights)
        if not total:
            return [], 1.0
        own_share = sum(w for _b, w, o in weights if o) / total
        rows = [{'beat': b.name, 'own': o, 'weight': w, 'share': round(w / total, 4)} for b, w, o in weights]
        return rows, own_share

    def _ff_compute_travel(self, employee, day):
        """The day's claim from the meter and the GPS track, split by route and priced per km."""
        employee = employee.sudo()
        history = self.env['ff.odometer.history']._ff_refresh(employee, day)
        rows, own_share = self._ff_beat_split(employee, day)
        # What is paid for: the meter when there is one, the tracked distance when the meter is not available.
        base = history.geo_km if history.na else history.odometer_km
        if employee._ff_day_vehicle(day)[1] == 'company':
            base = 0.0  # a company scooter is paid as DA, so there is no TA to claim
        own_km = round(base * own_share, 1)
        other_km = round(base - own_km, 1)
        own_rate, other_rate = self.env['ff.travel.rate']._ff_for_employee(employee)
        own_amount = round(own_km * own_rate, 2)
        other_amount = round(other_km * other_rate, 2)
        vals = {
            'basis': 'odometer', 'distance_km': base, 'rate_per_km': 0.0,
            'amount': own_amount + other_amount,
            'odometer_opening': history.opening, 'odometer_closing': history.closing,
            'odometer_km': history.odometer_km, 'odometer_na': history.na, 'geo_km': history.geo_km,
            'own_km': own_km, 'other_km': other_km, 'own_rate': own_rate, 'other_rate': other_rate,
            'own_amount': own_amount, 'other_amount': other_amount,
            'split_json': json.dumps(rows),
        }
        Claim = self.sudo()
        claim = Claim.search([('employee_id', '=', employee.id), ('date', '=', day)], limit=1)
        if claim and claim.state in ('submitted', 'approved'):
            return claim
        if claim:
            claim.write(dict(vals, state='draft'))
        else:
            claim = Claim.create(dict(vals, employee_id=employee.id, date=day))
        return claim

    def ff_submit_travel(self, employee, day):
        if employee.sudo()._ff_day_vehicle(day)[1] == 'company':
            raise UserError(self.env._('You were on a company scooter this day, which is paid as Daily Allowance, not TA.'))
        claim = self._ff_compute_travel(employee, day)
        if claim.state in ('submitted', 'approved'):
            raise UserError(self.env._('This day is already %s.', 'approved' if claim.state == 'approved'
                                       else 'with your manager for approval'))
        if not claim.distance_km:
            raise UserError(self.env._('There is no distance for this day to claim.'))
        claim.action_submit()
        return claim
