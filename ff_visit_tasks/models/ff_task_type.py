"""The kinds of task the field performs.

A master, so the report can group by it and the office can see what exists.
What each task captures is fixed in code - it is a sequence of screens - so
the master holds only what the office may change: the name, the order, and
whether the task is on or off.
"""
from odoo import fields, models


class FfTaskType(models.Model):
    _name = 'ff.task.type'
    _description = 'Field Task Type'
    _order = 'sequence, id'

    name = fields.Char(required=True, translate=True)
    code = fields.Selection([
        ('client_visit', 'Client Visit'),
        ('new_lead', 'New Lead'),
        ('lead_follow_up', 'New Lead Follow Up'),
        ('adhoc', 'Adhoc Task'),
        ('sample_collection', 'Sample Collection'),
        ('marketing_supply', 'Marketing Material Supply'),
    ], required=True, index=True)
    sequence = fields.Integer(default=10)
    steps = fields.Integer(string='Steps', help='How many screens the task has.')
    needs_contact = fields.Boolean(
        string='Needs a Contact', default=True,
        help='The salesperson picks the outlet or lead first. Off for a task done on the road.')
    hint = fields.Char(string='Shown in the app', translate=True)
    active = fields.Boolean(default=True)
    log_count = fields.Integer(compute='_compute_log_count')

    _code_uniq = models.Constraint('UNIQUE(code)', 'This task type already exists.')

    def _compute_log_count(self):
        counts = dict(self.env['ff.task.log']._read_group([('task_type_id', 'in', self.ids)],
                                                          ['task_type_id'], ['__count']))
        for task in self:
            task.log_count = counts.get(task, 0)

    def action_open_logs(self):
        self.ensure_one()
        return {
            'type': 'ir.actions.act_window', 'name': self.name, 'res_model': 'ff.task.log',
            'view_mode': 'list,form', 'domain': [('task_type_id', '=', self.id)],
        }
