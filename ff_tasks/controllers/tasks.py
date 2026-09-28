"""Tasks in the app: my list, moving one along, and giving one to my team."""
from odoo import http
from odoo.http import request

from odoo.addons.ff_base.tools import to_iso
from odoo.addons.ff_mobile_api.controllers.clients import to_int, visible_client
from odoo.addons.ff_mobile_api.controllers.common import ApiError, api_route, body, ok, ref


def task_data(task):
    return {
        'id': task.id,
        'name': task.name,
        'description': task.description or None,
        'employee': ref(task.employee_id),
        'customer': ref(task.partner_id),
        'due': task.date_deadline.isoformat() if task.date_deadline else None,
        'priority': task.priority or '0',
        'state': task.state,
        'is_overdue': task.is_overdue,
        'requires_photo': task.requires_photo,
        'assigned_by': task.assigned_by_employee_id.name or task.assigned_by_id.name or None,
        'started_at': to_iso(task.started_at),
        'done_at': to_iso(task.done_at),
        'done_note': task.done_note or None,
    }


def _task(employee, task_id, manage=False):
    task = request.env['ff.task'].sudo().browse(task_id).exists()
    allowed = task and (task.employee_id == employee or
                        (manage and task.employee_id in employee._ff_subordinates()))
    if not allowed:
        raise ApiError('Task not found.', 404, 'not_found')
    return task


class FieldForceTasksApi(http.Controller):

    @api_route('/api/v1/tasks', methods=('GET',))
    def tasks(self, employee, scope='mine', state=None, **kw):
        if scope == 'team' and not employee._ff_subordinates():
            raise ApiError('You have no team.', 403, 'forbidden')
        states = [s for s in (state or '').split(',') if s] or None
        tasks = request.env['ff.task'].ff_for_employee(employee, scope, states)
        open_tasks = tasks.filtered(lambda t: t.state in ('todo', 'in_progress'))
        return ok({
            'summary': {
                'open': len(open_tasks),
                'overdue': len(open_tasks.filtered('is_overdue')),
                'done': len(tasks.filtered(lambda t: t.state == 'done')),
            },
            'tasks': [task_data(task) for task in tasks],
        })

    @api_route('/api/v1/tasks/<int:task_id>', methods=('GET',))
    def task(self, employee, task_id, **kw):
        return ok(task_data(_task(employee, task_id, manage=True)))

    @api_route('/api/v1/tasks/<int:task_id>/<string:action>', methods=('POST',))
    def move(self, employee, task_id, action, **kw):
        states = {'start': 'in_progress', 'done': 'done'}
        if action not in states:
            raise ApiError('Unknown action.', 404, 'not_found')
        task = _task(employee, task_id).ff_set_state(employee, states[action], body())
        return ok(task_data(task))

    @api_route('/api/v1/tasks', methods=('POST',))
    def create(self, employee, **kw):
        data = body()
        if data.get('partner_id'):
            data['partner_id'] = visible_client(employee, to_int(data['partner_id'])).id
        task = request.env['ff.task'].ff_create_from_app(employee, data)
        return ok(task_data(task), status=201)
