from datetime import timedelta

from odoo import fields
from odoo.exceptions import UserError
from odoo.tests import TransactionCase, tagged


@tagged('post_install', '-at_install', 'ff')
class TestTasks(TransactionCase):

    @classmethod
    def setUpClass(cls):
        super().setUpClass()
        cls.manager = cls.env['hr.employee'].create({'name': 'Task Manager', 'ff_access_scope': 'hierarchy'})
        cls.officer = cls.env['hr.employee'].create({'name': 'Task Officer', 'parent_id': cls.manager.id})
        cls.other = cls.env['hr.employee'].create({'name': 'Someone Else'})

    def test_flow_from_the_app(self):
        task = self.env['ff.task'].ff_create_from_app(self.manager, {
            'name': 'Put up the poster', 'employee_id': self.officer.id, 'requires_photo': True})
        self.assertEqual(task.state, 'todo')
        self.assertEqual(task.assigned_by_employee_id, self.manager)
        with self.assertRaises(UserError):
            task.ff_set_state(self.other, 'in_progress', {})
        task.ff_set_state(self.officer, 'in_progress', {})
        self.assertEqual(task.state, 'in_progress')
        task.ff_set_state(self.officer, 'in_progress', {})  # a resend is not an error
        with self.assertRaises(UserError):
            task.ff_set_state(self.officer, 'done', {'note': 'done'})  # photo required
        task.ff_set_state(self.officer, 'done', {'note': 'done', 'photo': 'iVBORw0KGgo='})
        self.assertEqual(task.state, 'done')
        self.assertTrue(task.done_at)

    def test_only_team_members(self):
        with self.assertRaises(UserError):
            self.env['ff.task'].ff_create_from_app(self.manager, {'name': 'x', 'employee_id': self.other.id})

    def test_overdue(self):
        task = self.env['ff.task'].create({
            'name': 'Late', 'employee_id': self.officer.id,
            'date_deadline': fields.Date.context_today(self.env['ff.task']) - timedelta(days=2)})
        self.assertTrue(task.is_overdue)
        self.assertIn(task, self.env['ff.task'].search([('is_overdue', '=', True)]))
        task.action_done()
        self.assertFalse(task.is_overdue)
