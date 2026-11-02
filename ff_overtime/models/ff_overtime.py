"""Overtime: the hours worked beyond the shift, sent for approval, and turned into Compensatory Off hours."""
from datetime import timedelta

from odoo import api, fields, models
from odoo.exceptions import AccessError, UserError

# Less than this beyond the shift is not overtime.
MIN_OVERTIME_MINUTES = 15


class FfOvertime(models.Model):
    _name = 'ff.overtime'
    _description = 'Overtime'
    _inherit = ['mail.thread']
    _order = 'date desc, employee_id'

    employee_id = fields.Many2one('hr.employee', required=True, index=True, ondelete='cascade')
    date = fields.Date(required=True, index=True)
    worked_minutes = fields.Integer(readonly=True)
    expected_minutes = fields.Integer(string='Shift Minutes', readonly=True)
    overtime_minutes = fields.Integer(readonly=True, tracking=True)
    approved_minutes = fields.Integer(readonly=True, tracking=True,
                                      help='What the manager approved: it can be less than the overtime, or 0.')
    state = fields.Selection([
        ('draft', 'Not sent'), ('submitted', 'To Approve'), ('approved', 'Approved'), ('rejected', 'Rejected'),
    ], default='draft', required=True, index=True, tracking=True)
    decision_note = fields.Char(string='Manager\'s Reason', readonly=True, tracking=True,
                                help='Why the overtime was approved for less, or not at all.')
    approver_id = fields.Many2one('res.users', readonly=True, copy=False)
    decided_at = fields.Datetime(readonly=True, copy=False)
    allocation_id = fields.Many2one('hr.leave.allocation', readonly=True, copy=False, ondelete='set null')
    company_id = fields.Many2one(related='employee_id.company_id', store=True)

    _employee_date_uniq = models.Constraint('UNIQUE(employee_id, date)', 'One overtime record per employee and day.')

    @api.depends('employee_id', 'date')
    def _compute_display_name(self):
        for rec in self:
            rec.display_name = 'Overtime %s - %s' % (rec.employee_id.name or '', rec.date or '')

    # ------------------------------------------------------------------ what was worked
    @api.model
    def _ff_refresh(self, employee, first, last):
        """Work out the overtime of ``employee`` for the days from ``first`` to ``last`` from the punches.

        A day's overtime is the time worked beyond the hours of the shift; on a week off or a holiday all of it.
        Days not sent yet are kept up to date; sent and decided days are left as they are.
        """
        employee = employee.sudo()
        start, _dummy = employee._ff_day_bounds(first)
        _dummy, end = employee._ff_day_bounds(last)
        worked = {}
        for att in self.env['hr.attendance'].sudo().search([
                ('employee_id', '=', employee.id), ('check_in', '>=', start), ('check_in', '<', end),
                ('check_out', '!=', False)]):
            day = employee._ff_to_local(att.check_in).date()
            worked[day] = worked.get(day, 0.0) + att.worked_hours * 60.0
        existing = {r.date: r for r in self.sudo().search([('employee_id', '=', employee.id),
                                                           ('date', '>=', first), ('date', '<=', last)])}
        for day in {*worked, *existing}:
            rec = existing.get(day)
            if rec and rec.state != 'draft':
                continue
            off = bool(self.env['ff.holiday']._ff_for(employee, day))
            expected = 0 if off else int(round(employee._ff_expected_hours(day) * 60))
            extra = int(worked.get(day, 0.0) - expected)
            if extra < MIN_OVERTIME_MINUTES:
                if rec:
                    rec.unlink()
                continue
            vals = {'worked_minutes': int(worked[day]), 'expected_minutes': expected, 'overtime_minutes': extra}
            if rec:
                rec.write(vals)
            else:
                self.sudo().create(dict(vals, employee_id=employee.id, date=day))

    # ------------------------------------------------------------------ the employee
    def ff_send(self, employee):
        """Send the overtime days for approval."""
        rows = self.sudo().filtered(lambda r: r.employee_id == employee and r.state == 'draft')
        if not rows:
            raise UserError(self.env._('There is no overtime to send.'))
        rows.write({'state': 'submitted'})
        manager = employee.sudo().parent_id
        if manager and 'ff.notification' in self.env:
            minutes = sum(rows.mapped('overtime_minutes'))
            self.env['ff.notification'].sudo().ff_push(
                title=self.env._('Overtime to Approve'),
                body=self.env._('%(employee)s sent %(hours)s of overtime for approval.',
                                employee=employee.name, hours=_hours(minutes)),
                kind='approval', employee=manager, record=rows[:1])
        return rows

    # ------------------------------------------------------------------ the manager
    def ff_decide(self, approver, minutes, reject=False, note=''):
        """Approve ``minutes`` of the overtime (0 or a rejection refuses it)."""
        self.ensure_one()
        user = approver.sudo().user_id
        if not (user and user.has_group('ff_base.group_ff_admin')) and not approver._ff_is_manager_of(self.employee_id):
            raise AccessError(self.env._('This overtime is outside your data access.'))
        if self.state != 'submitted':
            raise UserError(self.env._('This overtime is not waiting for approval.'))
        minutes = max(0, min(int(minutes or 0), self.overtime_minutes))
        note = (note or '').strip()
        # Approving less than was sent, or nothing, needs a reason: the employee sees it.
        if (reject or minutes < self.overtime_minutes) and not note:
            raise UserError(self.env._('Give the reason for changing the overtime.'))
        rec = self.sudo()
        rec.decision_note = note or False
        if reject or minutes <= 0:
            rec.write({'state': 'rejected', 'approved_minutes': 0, 'approver_id': user.id or False,
                       'decided_at': fields.Datetime.now()})
        else:
            rec.write({'state': 'approved', 'approved_minutes': minutes, 'approver_id': user.id or False,
                       'decided_at': fields.Datetime.now()})
            rec._ff_grant_comp_off()
        if 'ff.notification' in self.env:
            self.env['ff.notification'].sudo().ff_push(
                title=self.env._('Overtime Approved') if rec.state == 'approved' else self.env._('Overtime Rejected'),
                body=((self.env._('%(hours)s of your overtime on %(date)s were approved and added to your '
                                  'compensatory off.', hours=_hours(rec.approved_minutes), date=rec.date)
                       + ((' ' + self.env._('You sent %(sent)s. Reason: %(why)s', sent=_hours(rec.overtime_minutes),
                                            why=note)) if note else ''))
                      if rec.state == 'approved' else
                      self.env._('Your overtime on %(date)s was not approved. %(why)s', date=rec.date, why=note)),
                kind='decision', employee=rec.employee_id, record=rec)
        return rec

    def _ff_grant_comp_off(self):
        """Add the approved time to the employee's Compensatory Off leave, in hours."""
        self.ensure_one()
        leave_type = self.env['hr.leave.type'].sudo().search(
            [('ff_comp_off', '=', True), ('company_id', 'in', (False, self.employee_id.company_id.id))], limit=1)
        if not leave_type:
            self.message_post(body=self.env._('No leave type is marked "Compensatory Off": nothing was added.'))
            return
        hours = self.approved_minutes / 60.0
        per_day = self.employee_id.sudo().resource_calendar_id.hours_per_day or 8.0
        allocation = self.env['hr.leave.allocation'].sudo().with_context(mail_create_nosubscribe=True).create({
            'name': self.env._('Overtime on %s', self.date),
            'holiday_status_id': leave_type.id,
            'employee_id': self.employee_id.id,
            'number_of_days': hours / per_day,
            'date_from': self.date,
        })
        if allocation.state != 'validate':
            allocation.action_validate()
        self.allocation_id = allocation.id


def _hours(minutes):
    """90 -> '1 h 30 min'."""
    minutes = int(minutes or 0)
    h, m = divmod(minutes, 60)
    return ('%d h ' % h if h else '') + ('%d min' % m if m or not h else '').strip()
