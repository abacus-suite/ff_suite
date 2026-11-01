"""Routes made in the field.

A route is usually drawn by the office, but the field is the side that finds
out a patch of town has been missed, or that one route has grown too big to
walk in a day. Letting them draw it there and then is the difference between a
route that exists and a note to somebody who will get to it next week.

Whether a new one is taken on trust or waits for the office to look at it is
the office's own decision, and it is a single setting.
"""
from datetime import timedelta

from odoo import api, fields, models
from odoo.exceptions import AccessError, UserError

APPROVAL_STATES = [
    ('approved', 'Approved'),
    ('pending', 'Pending Approval'),
    ('rejected', 'Rejected'),
]


def beats_need_approval(env):
    """Does a route drawn in the app wait for the office? Off unless set."""
    return env['ir.config_parameter'].sudo().get_param('ff_base.beat_approval') == 'True'


class FfBeatApp(models.Model):
    _inherit = 'ff.beat'

    ff_approval_state = fields.Selection(
        APPROVAL_STATES, string='Approval', default='approved', required=True, index=True, tracking=True,
        help='A route drawn in the app waits here when the office has asked to see new ones first.')
    ff_created_by_employee_id = fields.Many2one(
        'hr.employee', string='Drawn by (Field)', readonly=True, copy=False, index=True)
    ff_schedule = fields.Selection(
        [('one_time', 'One time'), ('recurrent', 'Recurrent')], string='Schedule',
        help='How a route drawn in the app is meant to be used.')
    ff_weekdays = fields.Char(string='Weekdays', help='Comma separated, Monday is 0. For a recurrent route.')
    ff_one_time_date = fields.Date(string='Date', help='The day a one time route is for.')

    def _ff_can_be_decided_by(self, employee):
        """Only somebody above whoever drew it may decide on it."""
        self.ensure_one()
        drawn_by = self.ff_created_by_employee_id
        return bool(drawn_by and employee and employee._ff_is_manager_of(drawn_by))

    # ------------------------------------------------------------------
    # From the app
    # ------------------------------------------------------------------
    @api.model
    def ff_create_from_app(self, employee, data):
        """Draw a route from the app. The city it covers is the one thing it must have."""
        name = (data.get('name') or '').strip()
        if not name:
            raise UserError(self.env._('Give the route a name.'))
        district = self.env['ff.district'].sudo().browse(int(data.get('district_id') or 0)).exists()
        if not district and data.get('territory_id'):
            territory_rec = self.env['ff.territory'].sudo().browse(int(data['territory_id'])).exists()
            if territory_rec and territory_rec.district_id:
                district = territory_rec.district_id
        if not district:
            district = self.env['ff.district'].sudo().search([], limit=1)
        if not district:
            raise UserError(self.env._('Choose the city this route covers.'))

        # A manager may draw a beat for somebody in their team: it is theirs to assign, so it needs no approval.
        owner = employee
        for_member = False
        member_ref = data.get('member')
        if member_ref not in (None, '', 'me') and str(member_ref).isdigit() and int(member_ref) != employee.id:
            owner = self.env['hr.employee'].sudo().browse(int(member_ref)).exists()
            if not owner or owner not in employee._ff_subordinates():
                raise AccessError(self.env._('You can draw a beat only for somebody in your team.'))
            for_member = True

        company = owner.company_id
        twin = self.sudo().search([
            ('name', '=ilike', name), ('district_id', '=', district.id),
            ('company_id', 'in', (False, company.id)),
        ], limit=1)
        if twin:
            raise UserError(self.env._('"%(name)s" already covers %(city)s.',
                                       name=twin.display_name, city=district.name))

        route_type = self.env['ff.route.type'].sudo().browse(int(data.get('route_type_id') or 0)).exists()
        if not route_type:
            # The app does not ask for a type: it is a Beat unless the office named it otherwise.
            types = self.env['ff.route.type'].ff_for_employee(owner)
            route_type = types.filtered(lambda t: (t.name or '').strip().lower() == 'beat')[:1] or types[:1]
        # A route drawn in the app always waits for the person's manager; with no manager it follows the setting.
        # A manager drawing one for somebody in the team decides it themselves.
        pending = False if for_member else (bool(employee.parent_id) or beats_need_approval(self.env))
        schedule = data.get('schedule') if data.get('schedule') in ('one_time', 'recurrent') else False
        weekdays = ','.join(sorted({str(int(d)) for d in (data.get('weekdays') or []) if str(d) in '0123456'}))
        if schedule == 'recurrent' and not weekdays:
            raise UserError(self.env._('Choose the weekdays this route repeats on.'))
        territory = {}
        if 'territory_id' in self._fields and data.get('territory_id'):
            territory = {'territory_id': int(data['territory_id'])}
        beat = self.sudo().create(dict(territory, **{
            'name': name,
            'code': (data.get('code') or '').strip() or False,
            'district_id': district.id,
            'state_id': district.state_id.id,
            'country_id': district.country_id.id,
            'route_type_id': route_type.id or False,
            'team_id': owner.ff_team_id.id or False,
            'company_id': company.id,
            'employee_ids': [(6, 0, owner.ids)],
            'ff_created_by_employee_id': employee.id,
            'ff_approval_state': 'pending' if pending else 'approved',
            'ff_schedule': schedule,
            'ff_weekdays': weekdays if schedule == 'recurrent' else False,
            'ff_one_time_date': data.get('date') if data.get('date') else False,
        }))
        partner_ids = data.get('partner_ids') or []
        if partner_ids:
            # Picked from the territory's own list, so they are put on as chosen, in the order of the list.
            Line = self.env['ff.beat.line'].sudo()
            wanted = self.env['res.partner'].sudo().browse([int(i) for i in partner_ids]).exists().filtered('active')
            sequence = 0
            for partner in wanted:
                sequence += 10
                Line.create({'beat_id': beat.id, 'partner_id': partner.id, 'sequence': sequence})
        if pending:
            manager = employee.parent_id
            if manager and 'activity_ids' in beat._fields and manager.user_id:
                try:
                    beat.activity_schedule(
                        'mail.mail_activity_data_todo', user_id=manager.user_id.id,
                        summary=self.env._('New route to approve: %s', beat.display_name))
                except Exception:
                    pass
            if manager and 'ff.notification' in self.env:
                self.env['ff.notification'].sudo().ff_push(
                    title=self.env._('New Beat to Approve'),
                    body=self.env._('%(who)s drew %(beat)s.', who=employee.name, beat=beat.name),
                    kind='approval',
                    employee=manager,
                    record=beat)
        else:
            beat._ff_make_weekly_template()
            beat._ff_auto_create_beat_plan()
            if for_member and 'ff.notification' in self.env:
                self.env['ff.notification'].sudo().ff_push(
                    title=self.env._('New Beat Assigned'),
                    body=self.env._('%(who)s assigned you the beat %(beat)s.', who=employee.name, beat=beat.name),
                    kind='info', employee=owner, record=beat)
        return beat

    @api.model
    def ff_add_customers_from_app(self, employee, beat, partner_ids):
        """Put customers on a route, at the end of it, skipping any already there."""
        beat = beat.sudo()
        if beat.ff_approval_state == 'rejected':
            raise UserError(self.env._('%s was rejected; it cannot be used.', beat.display_name))
        mine = beat.ff_created_by_employee_id == employee or employee in beat.employee_ids
        if not (mine or self.env['ff.beat'].ff_can_use_beat(employee, beat)):
            raise AccessError(self.env._('%s is not one of your routes.', beat.display_name))

        Partner = self.env['res.partner'].sudo()
        wanted = Partner.search(
            Partner._ff_visible_domain(employee) + [('id', 'in', [int(p) for p in partner_ids or []])])
        if not wanted:
            raise UserError(self.env._('Choose the customers to put on this route.'))
        already = beat.line_ids.partner_id
        sequence = max(beat.line_ids.mapped('sequence') or [0])
        Line = self.env['ff.beat.line'].sudo()
        added = Line.browse()
        for partner in wanted - already:
            sequence += 10
            added |= Line.create({'beat_id': beat.id, 'partner_id': partner.id, 'sequence': sequence})
        if added:
            beat._ff_send_back_for_approval(employee)
        return added

    def _ff_send_back_for_approval(self, employee):
        """An approved route that somebody edited waits for the manager again (Pending re-approval)."""
        self.ensure_one()
        manager = employee.parent_id
        if self.ff_approval_state != 'approved' or not manager:
            return
        vals = {'ff_approval_state': 'pending'}
        if not self.ff_created_by_employee_id:
            # So the manager can decide on it: a route the office assigned has nobody who drew it.
            vals['ff_created_by_employee_id'] = employee.id
        self.sudo().write(vals)
        if 'ff.notification' in self.env:
            self.env['ff.notification'].sudo().ff_push(
                title=self.env._('Beat to Approve Again'),
                body=self.env._('%(who)s changed %(beat)s.', who=employee.name, beat=self.name),
                kind='approval',
                employee=manager,
                record=self)

    def ff_app_payload(self):
        self.ensure_one()
        return {
            'id': self.id,
            'name': self.name,
            'code': self.code or None,
            'city': self.district_id.name or None,
            'district_id': self.district_id.id or None,
            'route_type': self.route_type_id.name or None,
            'customer_count': len(self.line_ids),
            'approval_state': self.ff_approval_state,
            'schedule': self.ff_schedule or None,
            'weekdays': [int(d) for d in (self.ff_weekdays or '').split(',') if d],
            'date': self.ff_one_time_date.isoformat() if self.ff_one_time_date else None,
            'mine': self.ff_created_by_employee_id.id or None,
        }

    # ------------------------------------------------------------------
    # The office decides
    # ------------------------------------------------------------------
    def action_ff_approve(self):
        self._ff_decide(True)

    def action_ff_reject(self):
        self._ff_decide(False)

    def _ff_decide(self, approve):
        for beat in self:
            if beat.ff_approval_state != 'pending':
                raise UserError(self.env._('%s is not waiting for a decision.', beat.display_name))
        self.sudo().write({'ff_approval_state': 'approved' if approve else 'rejected'})
        if 'activity_ids' in self._fields:
            self.activity_ids.unlink()
        if approve:
            self._ff_make_weekly_template()
            self._ff_auto_create_beat_plan()
        if 'ff.notification' in self.env:
            for beat in self:
                who = beat.ff_created_by_employee_id or beat.employee_ids[:1]
                if who:
                    self.env['ff.notification'].sudo().ff_push(
                        title=self.env._('Beat Plan Approved') if approve else self.env._('Beat Plan Rejected'),
                        body=self.env._('Beat plan %(name)s was %(status)s.',
                                        name=beat.display_name,
                                        status=self.env._('approved') if approve else self.env._('rejected')),
                        kind='decision',
                        employee=who,
                        record=beat,
                    )

    def _ff_auto_create_beat_plan(self):
        """When a beat is approved, automatically create the daily route plan(s)
        (ff.beat.plan) for the employee based on the selected date and recurrence schedule."""
        Day = self.env['ff.beat.plan'].sudo()
        today = fields.Date.context_today(self)

        for beat in self:
            drawn_by = beat.ff_created_by_employee_id
            # A beat a manager drew for somebody is planned on that person's days, not the manager's.
            employee = beat.employee_ids[:1] if (beat.employee_ids and drawn_by not in beat.employee_ids) \
                else (drawn_by or beat.employee_ids[:1])
            if not employee:
                continue

            # Ensure the beat is assigned to employee so route constraints pass
            if beat not in employee.ff_route_ids:
                employee.sudo().write({'ff_route_ids': [(4, beat.id)]})

            schedule = beat.ff_schedule or 'one_time'
            start_date = beat.ff_one_time_date or today

            target_dates = []
            if schedule == 'one_time':
                if start_date:
                    target_dates.append(start_date)
            elif schedule == 'recurrent':
                weekdays = [int(d) for d in (beat.ff_weekdays or '').split(',') if d.isdigit()]
                if not weekdays and start_date:
                    weekdays = [start_date.weekday()]

                cur = start_date if start_date >= today else today
                # Auto-plan for the next 4 weeks (28 days) matching recurring weekdays
                end_date = cur + timedelta(days=28)
                while cur <= end_date:
                    if cur.weekday() in weekdays:
                        target_dates.append(cur)
                    cur += timedelta(days=1)

                if start_date >= today and start_date not in target_dates:
                    target_dates.append(start_date)
                target_dates.sort()

            # Create daily beat plans for the target dates
            for day_date in target_dates:
                existing = Day.search([
                    ('employee_id', '=', employee.id),
                    ('date', '=', day_date),
                ])
                if existing:
                    if beat in existing.beat_id:
                        continue
                    if employee.ff_routes_per_day == 'single':
                        continue

                try:
                    Day.with_context(ff_manager_plan=True).create({
                        'employee_id': employee.id,
                        'beat_id': beat.id,
                        'date': day_date,
                    })
                except Exception:
                    pass

    @api.model
    def _cron_archive_one_time(self):
        """A one-time beat is for its date only: once that day has passed, or its plan is done, it leaves the
        beat list (archived, so the plans and visits made on it keep their history)."""
        today = fields.Date.context_today(self)
        beats = self.sudo().search([('ff_schedule', '=', 'one_time'), ('ff_one_time_date', '!=', False),
                                    ('ff_one_time_date', '<=', today)])
        finished = self.browse()
        for beat in beats:
            if beat.ff_one_time_date < today:
                finished |= beat
                continue
            plans = self.env['ff.beat.plan'].sudo().search([('beat_id', '=', beat.id), ('date', '=', today)])
            if plans and all(plan.status == 'done' for plan in plans):
                finished |= beat
        finished.write({'active': False})

    def _ff_make_weekly_template(self):
        """An approved recurrent route becomes a weekly plan template for whoever drew it, so the office
        can apply it to their days."""
        Template = self.env['ff.route.plan.template'].sudo()
        for beat in self.filtered(lambda b: b.ff_schedule == 'recurrent' and b.ff_weekdays):
            who = beat.employee_ids[:1] if (beat.employee_ids and beat.ff_created_by_employee_id not in beat.employee_ids) \
                else beat.ff_created_by_employee_id
            Template.create({
                'name': '%s - %s' % (beat.display_name, who.name or ''),
                'employee_id': who.id or False,
                'company_id': beat.company_id.id or self.env.company.id,
                'line_ids': [(0, 0, {'weekday': day, 'week': 'all', 'beat_id': beat.id})
                             for day in beat.ff_weekdays.split(',') if day],
            })

    def ff_decide_from_app(self, employee, approve):
        """A manager approves a route their own field drew."""
        self.ensure_one()
        if not self._ff_can_be_decided_by(employee):
            raise AccessError(self.env._('This route is outside your data access.'))
        self._ff_decide(approve)
        return self
