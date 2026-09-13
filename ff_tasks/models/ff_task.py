"""Tasks the office (or a manager in the app) gives to field staff."""
from odoo import api, fields, models
from odoo.exceptions import UserError

from odoo.addons.ff_app_reports.models.ff_app_report import DATE, STATUS, TEXT, col

STATES = [
    ('todo', 'To Do'),
    ('in_progress', 'In Progress'),
    ('done', 'Done'),
    ('cancelled', 'Cancelled'),
]
PRIORITIES = [('0', 'Normal'), ('1', 'High'), ('2', 'Urgent')]


class FfTask(models.Model):
    _name = 'ff.task'
    _description = 'Field Task'
    _inherit = ['mail.thread', 'mail.activity.mixin']
    _order = 'priority desc, date_deadline, id desc'

    name = fields.Char(string='Task', required=True, tracking=True)
    description = fields.Text()
    employee_id = fields.Many2one('hr.employee', string='Assigned To', required=True, index=True,
                                  ondelete='cascade', tracking=True)
    team_id = fields.Many2one(related='employee_id.ff_team_id', store=True)
    department_id = fields.Many2one(related='employee_id.department_id', store=True)
    partner_id = fields.Many2one('res.partner', string='Customer', index=True, tracking=True,
                                 help='Where the task is done, when it is at a customer.')
    date_deadline = fields.Date(string='Due', index=True, tracking=True)
    priority = fields.Selection(PRIORITIES, default='0', tracking=True)
    state = fields.Selection(STATES, default='todo', required=True, index=True, tracking=True)
    assigned_by_id = fields.Many2one('res.users', default=lambda self: self.env.user, readonly=True)
    assigned_by_employee_id = fields.Many2one('hr.employee', string='Assigned By (App)', readonly=True)
    requires_photo = fields.Boolean(string='Photo Required to Finish')
    started_at = fields.Datetime(readonly=True)
    done_at = fields.Datetime(readonly=True, tracking=True)
    done_note = fields.Text(string='Completion Note')
    done_lat = fields.Float(digits=(10, 7), readonly=True)
    done_lng = fields.Float(digits=(10, 7), readonly=True)
    visit_id = fields.Many2one('ff.visit', string='Visit', readonly=True, ondelete='set null')
    is_overdue = fields.Boolean(compute='_compute_is_overdue', search='_search_is_overdue')
    company_id = fields.Many2one(related='employee_id.company_id', store=True)

    def _compute_is_overdue(self):
        today = fields.Date.context_today(self)
        for task in self:
            task.is_overdue = bool(task.date_deadline and task.date_deadline < today
                                   and task.state in ('todo', 'in_progress'))

    def _search_is_overdue(self, operator, value):
        today = fields.Date.context_today(self)
        overdue = [('date_deadline', '<', today), ('state', 'in', ('todo', 'in_progress'))]
        if (operator == '=') == bool(value):
            return overdue
        return ['|', '|', ('date_deadline', '=', False), ('date_deadline', '>=', today),
                ('state', 'not in', ('todo', 'in_progress'))]

    # ------------------------------------------------------------------
    # Notifications
    # ------------------------------------------------------------------
    def _ff_tell(self, title, body, employee):
        if 'ff.notification' in self.env and employee:
            self.env['ff.notification'].ff_push(title, body, employee=employee, record=self)

    @api.model_create_multi
    def create(self, vals_list):
        tasks = super().create(vals_list)
        for task in tasks:
            due = ' (due %s)' % task.date_deadline.strftime('%d %b') if task.date_deadline else ''
            task._ff_tell('New task', '%s%s' % (task.name, due), task.employee_id)
        return tasks

    def write(self, vals):
        reassigned = 'employee_id' in vals
        result = super().write(vals)
        if reassigned:
            for task in self:
                task._ff_tell('Task assigned to you', task.name, task.employee_id)
        return result

    # ------------------------------------------------------------------
    # Office buttons
    # ------------------------------------------------------------------
    def action_start(self):
        self.filtered(lambda t: t.state == 'todo').write({'state': 'in_progress', 'started_at': fields.Datetime.now()})

    def action_done(self):
        self.write({'state': 'done', 'done_at': fields.Datetime.now()})

    def action_cancel(self):
        self.write({'state': 'cancelled'})

    def action_reopen(self):
        self.write({'state': 'todo', 'done_at': False})

    # ------------------------------------------------------------------
    # From the app
    # ------------------------------------------------------------------
    @api.model
    def ff_for_employee(self, employee, scope='mine', states=None):
        domain = [('employee_id', '=', employee.id)]
        if scope == 'team':
            domain = [('employee_id', 'in', employee._ff_subordinates().ids)]
        if states:
            domain.append(('state', 'in', states))
        return self.sudo().search(domain, limit=200)

    def ff_set_state(self, employee, state, data):
        """Move a task along from the app. Only its assignee may; finishing may need a photo."""
        self.ensure_one()
        task = self.sudo()
        if task.employee_id != employee:
            raise UserError(self.env._('This task is assigned to someone else.'))
        if state not in ('in_progress', 'done'):
            raise UserError(self.env._('A task can only be started or finished from the app.'))
        if task.state in ('done', 'cancelled'):
            raise UserError(self.env._('This task is already closed.'))
        vals = {'state': state}
        if state == 'in_progress':
            vals['started_at'] = fields.Datetime.now()
        else:
            photo = data.get('photo')
            if task.requires_photo and not photo:
                raise UserError(self.env._('Add a photo to finish this task.'))
            vals.update(done_at=fields.Datetime.now(), done_note=data.get('note') or False,
                        done_lat=data.get('lat') or 0.0, done_lng=data.get('lng') or 0.0)
            ongoing = self.env['ff.visit'].sudo().search(
                [('employee_id', '=', employee.id), ('state', '=', 'ongoing')], limit=1)
            if ongoing:
                vals['visit_id'] = ongoing.id
            if photo:
                if ',' in photo[:80]:
                    photo = photo.split(',', 1)[1]
                self.env['ir.attachment'].sudo().create({
                    'name': 'task_%s_proof.jpg' % task.id, 'datas': photo, 'res_model': self._name,
                    'res_id': task.id, 'mimetype': 'image/jpeg'})
            if task.assigned_by_employee_id:
                task._ff_tell('Task done', '%s finished: %s' % (employee.name, task.name), task.assigned_by_employee_id)
        task.write(vals)
        if state == 'done':
            task.message_post(body=self.env._('Finished from the app by %s.', employee.name))
        return task

    @api.model
    def ff_create_from_app(self, manager, data):
        """A manager hands a task to someone in their team."""
        team = manager._ff_subordinates()
        assignee = self.env['hr.employee'].sudo().browse(int(data.get('employee_id') or 0)).exists()
        if not assignee or assignee not in (team | manager):
            raise UserError(self.env._('You can only give tasks to your team.'))
        if not (data.get('name') or '').strip():
            raise UserError(self.env._('Give the task a title.'))
        vals = {
            'name': data['name'].strip(),
            'description': data.get('description') or False,
            'employee_id': assignee.id,
            'date_deadline': data.get('date_deadline') or False,
            'priority': str(data.get('priority') or '0'),
            'requires_photo': bool(data.get('requires_photo')),
            'assigned_by_employee_id': manager.id,
        }
        if data.get('partner_id'):
            vals['partner_id'] = int(data['partner_id'])
        return self.sudo().create(vals)


class FfAppReportTasks(models.AbstractModel):
    _inherit = 'ff.app.report'

    def _definitions(self):
        defs = super()._definitions()
        defs['tasks'] = ('Tasks', 'Tasks given, done and overdue', 'task_alt', 'ff.task', [
            col('date', 'Due', DATE), col('employee', 'Employee'), col('task', 'Task'),
            col('customer', 'Customer'), col('priority', 'Priority'), col('done_at', 'Finished', TEXT),
            col('status', 'Status', STATUS)], self._tasks)
        return defs

    def _tasks(self, employees, start, end):
        tasks = self.env['ff.task'].sudo().search([
            ('employee_id', 'in', employees.ids), '|', ('date_deadline', '=', False),
            '&', ('date_deadline', '>=', start), ('date_deadline', '<=', end)], order='date_deadline desc')
        today = fields.Date.context_today(self)
        return [{
            'date': task.date_deadline.isoformat() if task.date_deadline else None,
            'employee': task.employee_id.name,
            'task': task.name,
            'customer': task.partner_id.display_name or '',
            'priority': dict(PRIORITIES)[task.priority or '0'],
            'done_at': task.employee_id._ff_to_local(task.done_at).strftime('%d %b %H:%M') if task.done_at else '',
            'status': 'Overdue' if task.date_deadline and task.date_deadline < today
            and task.state in ('todo', 'in_progress') else dict(STATES)[task.state],
        } for task in tasks]

