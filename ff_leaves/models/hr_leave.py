"""Time off, seen from the field app.

Odoo already models leave properly - types, allocations, approval steps - so the
app asks it questions rather than keeping its own version of the truth.
"""
from odoo import api, fields, models
from odoo.exceptions import AccessError, UserError

APP_STATES = {
    'draft': 'Draft',
    'confirm': 'Waiting approval',
    'refuse': 'Refused',
    'validate1': 'Second approval',
    'validate': 'Approved',
    'cancel': 'Cancelled',
}


VALIDATION_LABELS = {
    'no_validation': 'No approval needed',
    'hr': 'Approved by the Time Off officer',
    'manager': "Approved by the employee's manager",
    'both': 'Manager, then Time Off officer',
}


class HrLeaveType(models.Model):
    _inherit = 'hr.leave.type'

    ff_show_in_app = fields.Boolean(
        string='Request from Field Force App', default=False,
        help='Only types with this ticked are shown in the Field Force app. '
             'Types left unticked are hidden in the app.')


class HrLeave(models.Model):
    _inherit = 'hr.leave'

    def _ff_hour(self, name):
        """The start or end time of a request made by the hour, or None (the field differs between versions)."""
        if name not in self._fields or not getattr(self, 'request_unit_hours', False):
            return None
        try:
            return float(self[name]) if self[name] else None
        except (TypeError, ValueError):
            return None

    def ff_app_payload(self):
        self.ensure_one()
        return {
            'id': self.id,
            'type': {'id': self.holiday_status_id.id, 'name': self.holiday_status_id.name},
            'from': self.request_date_from and self.request_date_from.isoformat(),
            'to': self.request_date_to and self.request_date_to.isoformat(),
            'days': self.number_of_days,
            'hours': round(self.number_of_hours or 0.0, 2) if 'number_of_hours' in self._fields else None,
            'hour_from': self._ff_hour('request_hour_from'),
            'hour_to': self._ff_hour('request_hour_to'),
            'half_day': self.request_unit_half,
            'half_day_period': (self.request_date_from_period or None)
            if self.request_unit_half and 'request_date_from_period' in self._fields else None,
            'state': self.state,
            'state_label': APP_STATES.get(self.state, self.state),
            'reason': self.private_name or self.name or '',
            'employee': {'id': self.employee_id.id, 'name': self.employee_id.name},
            'can_cancel': self.state in ('draft', 'confirm'),
            'requested_on': fields.Datetime.to_string(self.create_date) if self.create_date else None,
            'approval': self._ff_approval_payload(),
        }

    def _ff_approval_payload(self):
        """How this request gets approved; the approval chain module adds its steps."""
        self.ensure_one()
        kind = self.holiday_status_id.leave_validation_type if 'leave_validation_type' in self.holiday_status_id._fields else ''
        steps = []
        if kind in ('manager', 'both'):
            manager = self.employee_id.leave_manager_id if 'leave_manager_id' in self.employee_id._fields else False
            steps.append({'name': 'Manager', 'approver': manager.name if manager else 'Manager',
                          'state': 'done' if self.state in ('validate1', 'validate') else
                          'rejected' if self.state == 'refuse' else 'pending'})
        if kind in ('hr', 'both'):
            steps.append({'name': 'Time Off officer', 'approver': 'HR',
                          'state': 'done' if self.state == 'validate' else
                          'rejected' if self.state == 'refuse' else
                          'waiting' if kind == 'both' and self.state == 'confirm' else 'pending'})
        return {'source': 'odoo', 'label': VALIDATION_LABELS.get(kind, ''), 'steps': steps}

    # ------------------------------------------------------------------
    @api.model
    def _ff_app_types(self, employee):
        """Types offered in the app: only the ticked ones."""
        Type = self.env['hr.leave.type'].sudo().with_context(
            employee_id=employee.id, default_employee_id=employee.id)
        domain = [('company_id', 'in', (False, employee.company_id.id))]
        if 'active' in Type._fields:
            domain.append(('active', '=', True))
        return Type.search(domain + [('ff_show_in_app', '=', True)])

    @api.model
    def ff_types_for(self, employee):
        """Leave types this employee may ask for, with allocated, used, pending and what is left."""
        rows = []
        Leave = self.sudo()
        year_start = fields.Date.context_today(self).replace(month=1, day=1)
        for leave_type in self._ff_app_types(employee):
            def number(name):
                return round(float(getattr(leave_type, name, 0.0) or 0.0), 2) if name in leave_type._fields else 0.0
            taken = Leave.search([('employee_id', '=', employee.id), ('holiday_status_id', '=', leave_type.id),
                                  ('state', '=', 'validate'), ('request_date_from', '>=', year_start)])
            pending = Leave.search([('employee_id', '=', employee.id), ('holiday_status_id', '=', leave_type.id),
                                    ('state', 'in', ('confirm', 'validate1'))])
            requires = leave_type.requires_allocation in ('yes', True)
            allocated = number('max_leaves')
            used = number('leaves_taken') if 'leaves_taken' in leave_type._fields else round(sum(taken.mapped('number_of_days')), 2)
            pending_days = round(sum(pending.mapped('number_of_days')), 2)
            remaining = number('virtual_remaining_leaves')
            if leave_type.request_unit == 'hour':
                # Asked for by the hour: the balance is in hours too (what was given, used, waiting, left).
                per_day = employee.sudo().resource_calendar_id.hours_per_day or 8.0
                given = sum(a.number_of_days * per_day for a in self.env['hr.leave.allocation'].sudo().search([
                    ('employee_id', '=', employee.id), ('holiday_status_id', '=', leave_type.id),
                    ('state', '=', 'validate')])) if 'hr.leave.allocation' in self.env else 0.0
                allocated = round(given, 2)
                used = round(sum(Leave.search([
                    ('employee_id', '=', employee.id), ('holiday_status_id', '=', leave_type.id),
                    ('state', '=', 'validate')]).mapped('number_of_hours')), 2)
                pending_days = round(sum(pending.mapped('number_of_hours')), 2)
                remaining = round(allocated - used - pending_days, 2)
            rows.append({
                'id': leave_type.id,
                'name': leave_type.name,
                'requires_allocation': requires,
                'allocated': allocated if requires else None,
                'used': used,
                'used_this_year': round(sum(taken.mapped('number_of_days')), 2),
                'pending': pending_days,
                'remaining': remaining if requires else None,
                'unit': leave_type.request_unit,
                'colour': leave_type.color or 0,
                'approval': VALIDATION_LABELS.get(getattr(leave_type, 'leave_validation_type', ''), ''),
                'can_request': (not requires) or remaining > 0,
            })
        return rows

    @api.model
    def ff_allocations_for(self, employee):
        """Days given to this employee per type, with the period they cover."""
        if 'hr.leave.allocation' not in self.env:
            return []
        Allocation = self.env['hr.leave.allocation'].sudo()
        allowed = self._ff_app_types(employee)
        allocations = Allocation.search([('employee_id', '=', employee.id), ('state', '=', 'validate'),
                                         ('holiday_status_id', 'in', allowed.ids)], order='date_from desc')
        return [{
            'id': allocation.id,
            'type': {'id': allocation.holiday_status_id.id, 'name': allocation.holiday_status_id.name},
            'days': round(allocation.number_of_days or 0.0, 2),
            'used': round(getattr(allocation, 'leaves_taken', 0.0) or 0.0, 2) if 'leaves_taken' in allocation._fields else None,
            'from': allocation.date_from.isoformat() if allocation.date_from else None,
            'to': allocation.date_to.isoformat() if allocation.date_to else None,
            'name': allocation.name or '',
            'kind': allocation.allocation_type if 'allocation_type' in allocation._fields else 'regular',
        } for allocation in allocations]

    @api.model
    def ff_my_leaves(self, employee, limit=50):
        leaves = self.sudo().search([('employee_id', '=', employee.id)],
                                    order='request_date_from desc', limit=limit)
        return [leave.ff_app_payload() for leave in leaves]

    @api.model
    def ff_request_from_app(self, employee, data):
        """Raise a leave request for this employee, as that employee."""
        leave_type = self.env['hr.leave.type'].sudo().browse(int(data.get('type_id') or 0)).exists()
        if not leave_type:
            raise UserError(self.env._('Choose a leave type.'))
        if leave_type not in self._ff_app_types(employee):
            raise UserError(self.env._('%s cannot be requested from the app.', leave_type.name))
        date_from = fields.Date.to_date(data.get('from'))
        date_to = fields.Date.to_date(data.get('to')) or date_from
        if not date_from:
            raise UserError(self.env._('Choose the days you are asking for.'))
        if date_to < date_from:
            date_from, date_to = date_to, date_from
        values = {
            'holiday_status_id': leave_type.id,
            'employee_id': employee.id,
            'request_date_from': date_from,
            'request_date_to': date_to,
            'name': (data.get('reason') or '').strip() or self.env._('Requested from the app'),
        }
        if leave_type.request_unit == 'hour' and data.get('hour_from') is not None:
            # By the hour: one day, from a time to a time.
            try:
                hour_from, hour_to = float(data['hour_from']), float(data['hour_to'])
            except (TypeError, ValueError, KeyError):
                raise UserError(self.env._('Choose the time you are asking for.'))
            if hour_to <= hour_from:
                raise UserError(self.env._('The end time must be after the start time.'))
            kind = self._fields['request_hour_from'].type
            convert = (lambda v: '%g' % v) if kind == 'selection' else float
            values.update({'request_unit_hours': True, 'request_date_to': date_from,
                           'request_hour_from': convert(hour_from), 'request_hour_to': convert(hour_to)})
        elif data.get('half_day'):
            values.update({'request_unit_half': True, 'request_date_to': date_from})
            if 'request_date_from_period' in self._fields:
                values['request_date_from_period'] = 'pm' if data.get('half_day_period') == 'pm' else 'am'
        leave = self.sudo().with_context(
            mail_create_nosubscribe=True, leave_skip_date_check=True).create(values)
        manager = employee.parent_id or (getattr(employee, 'leave_manager_id', False) and employee.leave_manager_id.sudo().employee_id)
        if manager and 'ff.notification' in self.env:
            self.env['ff.notification'].sudo().ff_push(
                title=self.env._('Leave to Approve'),
                body=self.env._('%(employee)s requested leave (%(from_date)s to %(to_date)s).',
                                employee=employee.name,
                                from_date=date_from,
                                to_date=date_to),
                kind='approval',
                employee=manager,
                record=leave,
            )
        return leave

    @api.model
    def ff_team_balances(self, employee):
        """Each person in my team: totals per type, who is off now and what is waiting."""
        team = employee._ff_subordinates().sorted('name')
        today = fields.Date.context_today(self)
        rows = []
        for member in team:
            types = self.ff_types_for(member)
            current = self.sudo().search([('employee_id', '=', member.id), ('state', '=', 'validate'),
                                          ('request_date_from', '<=', today), ('request_date_to', '>=', today)], limit=1)
            upcoming = self.sudo().search([('employee_id', '=', member.id), ('state', 'in', ('confirm', 'validate1', 'validate')),
                                           ('request_date_from', '>', today)], order='request_date_from', limit=3)
            rows.append({
                'employee': {'id': member.id, 'name': member.name, 'code': member.ff_employee_code or None,
                             'job': member.job_title or None},
                'allocated': round(sum(t['allocated'] or 0 for t in types), 2),
                'used': round(sum(t['used'] or 0 for t in types), 2),
                'pending': round(sum(t['pending'] or 0 for t in types), 2),
                'remaining': round(sum(t['remaining'] or 0 for t in types if t['requires_allocation']), 2),
                'types': types,
                'on_leave_today': current.ff_app_payload() if current else None,
                'upcoming': [leave.ff_app_payload() for leave in upcoming],
            })
        return rows

    @api.model
    def ff_calendar(self, employee, start, end, member=None):
        """Approved and waiting leave of me and my team between two dates."""
        people = employee | employee._ff_subordinates()
        if member not in (None, '', 'team', 'me'):
            people = people.filtered(lambda p: p.id == int(member))
        elif member == 'me':
            people = employee
        leaves = self.sudo().search([
            ('employee_id', 'in', people.ids), ('state', 'in', ('confirm', 'validate1', 'validate')),
            ('request_date_from', '<=', end), ('request_date_to', '>=', start),
        ], order='request_date_from')
        return [leave.ff_app_payload() for leave in leaves]

    @api.model
    def ff_check_overlap(self, employee, date_from, date_to):
        """What a leave would clash with: planned route days and other leave."""
        warnings = []
        if 'ff.beat.plan' in self.env:
            days = self.env['ff.beat.plan'].sudo().search([
                ('employee_id', '=', employee.id), ('date', '>=', date_from), ('date', '<=', date_to)], order='date')
            for day in days:
                customers = len(day.customer_line_ids.filtered(lambda l: l.selected and not l.visit_id))
                warnings.append({'kind': 'beat_plan', 'date': day.date.isoformat(),
                                 'message': '%s: %s planned (%d customers)' % (
                                     day.date.isoformat(), day.beat_id.display_name, customers)})
        if 'ff.task' in self.env:
            for task in self.env['ff.task'].sudo().search([
                    ('employee_id', '=', employee.id), ('state', 'in', ('todo', 'in_progress')),
                    ('date_deadline', '>=', date_from), ('date_deadline', '<=', date_to)]):
                warnings.append({'kind': 'task', 'date': task.date_deadline.isoformat(),
                                 'message': 'Task due %s: %s' % (task.date_deadline.isoformat(), task.name)})
        clash = self.sudo().search([
            ('employee_id', '=', employee.id), ('state', 'in', ('confirm', 'validate1', 'validate')),
            ('request_date_from', '<=', date_to), ('request_date_to', '>=', date_from)], limit=1)
        if clash:
            warnings.append({'kind': 'leave', 'date': clash.request_date_from.isoformat(),
                             'message': 'You already have %s on these days (%s)' % (
                                 clash.holiday_status_id.name, APP_STATES.get(clash.state, clash.state))})
        return warnings

    @api.model
    def ff_to_approve(self, employee):
        """What this manager has waiting, inside their data access."""
        team = employee._ff_approval_team()
        leaves = self.sudo().search([
            ('employee_id', 'in', team.ids), ('state', 'in', ('confirm', 'validate1')),
        ], order='request_date_from') if team else self.browse()
        rows = [leave.ff_app_payload() for leave in leaves]
        # Approved leaves the employee wants cancelled, waiting for this person.
        if 'ff.leave.cancel' in self.env:
            try:
                with self.env.cr.savepoint():
                    for cancel in self.env['ff.leave.cancel'].sudo().search([('state', 'in', ('manager', 'hr'))]):
                        if cancel._ff_awaits(employee):
                            payload = cancel.leave_id.ff_app_payload()
                            payload.update({'cancel_request': True, 'state_label': 'Cancellation requested',
                                            'reason': cancel.reason or payload.get('reason')})
                            rows.append(payload)
            except Exception:  # noqa: BLE001 - never let the cancellations hide the leaves to approve
                pass
        return rows

    def ff_decide_as(self, employee, approve, reason=''):
        """Approve or refuse, with the manager's own rights checked first."""
        self.ensure_one()
        if self.employee_id not in employee._ff_approval_team():
            raise AccessError(self.env._('This request is not yours to decide.'))
        leave = self.sudo()
        if approve:
            leave.action_approve()
        else:
            leave.action_refuse()
            if reason:
                leave.message_post(body=reason)
        if 'ff.notification' in self.env and self.employee_id:
            title = self.env._('Leave Request Approved') if approve else self.env._('Leave Request Refused')
            body = self.env._('Your leave request (%(from_date)s to %(to_date)s) was %(status)s by %(manager)s.%(note)s',
                              from_date=self.request_date_from, to_date=self.request_date_to,
                              status=self.env._('approved') if approve else self.env._('refused'),
                              manager=employee.name,
                              note=(': ' + reason) if reason else '')
            self.env['ff.notification'].sudo().ff_push(
                title=title, body=body, kind='decision',
                employee=self.employee_id, record=self
            )
        return leave

    def ff_cancel_as(self, employee):
        self.ensure_one()
        if self.employee_id != employee:
            raise AccessError(self.env._('This request is not yours.'))
        if self.state not in ('draft', 'confirm'):
            raise UserError(self.env._('An approved request cannot be withdrawn from the app.'))
        self.sudo().unlink()
        return True
