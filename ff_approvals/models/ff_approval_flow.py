"""Who signs what, in which order.

A claim rarely needs one signature. A company will want the reporting manager
first, then the branch head, and above some amount the finance desk as well. A
flow says that once; every document of that kind then carries its own copy of
the steps, so changing the rule later does not rewrite history.
"""
from odoo import api, fields, models
from odoo.exceptions import ValidationError

DOCUMENT_KINDS = [
    ('ff.expense.claim', 'Expense Claim'),
    ('ff.allowance.claim', 'Travel Allowance'),
]

APPROVER_KINDS = [
    ('manager', 'Reporting manager'),
    ('department_manager', 'Department manager'),
    ('team_manager', 'Team manager'),
    ('user', 'A specific person'),
]


class FfApprovalFlow(models.Model):
    _name = 'ff.approval.flow'
    _description = 'Approval Flow'
    _order = 'sequence, id'

    name = fields.Char(required=True, translate=True)
    sequence = fields.Integer(default=10)
    document = fields.Selection(DOCUMENT_KINDS, required=True, index=True,
                                help='Which kind of document this flow signs off.')
    active = fields.Boolean(default=True)
    company_id = fields.Many2one('res.company', required=True, default=lambda self: self.env.company)

    # Narrow a flow to part of the organisation; the most specific one wins.
    department_ids = fields.Many2many('hr.department', string='Departments',
                                      help='Leave empty for every department.')
    team_ids = fields.Many2many('ff.team', string='Teams', help='Leave empty for every team.')
    employee_ids = fields.Many2many('hr.employee', string='Employees',
                                    help='Leave empty for everybody in the scope above.')
    min_amount = fields.Monetary(string='From Amount', help='Use this flow only above this amount. 0 = always.')
    currency_id = fields.Many2one(related='company_id.currency_id')

    step_ids = fields.One2many('ff.approval.step', 'flow_id', string='Steps', copy=True)
    step_count = fields.Integer(compute='_compute_step_count')

    @api.depends('step_ids')
    def _compute_step_count(self):
        for flow in self:
            flow.step_count = len(flow.step_ids)

    @api.constrains('step_ids')
    def _check_steps(self):
        for flow in self:
            if not flow.step_ids:
                raise ValidationError(self.env._('A flow needs at least one approver.'))

    # ------------------------------------------------------------------
    @api.model
    def ff_flow_for(self, document):
        """The flow that applies to this document, or none.

        More specific beats more general: a flow naming the employee wins over
        one naming their team, which wins over one naming the department, which
        wins over a company-wide flow. Amount thresholds are read the same way -
        the highest threshold the document clears.
        """
        employee = document.employee_id
        amount = getattr(document, 'amount', 0.0) or 0.0
        flows = self.sudo().search([
            ('document', '=', document._name),
            ('company_id', 'in', (False, employee.company_id.id)),
            ('min_amount', '<=', amount),
        ])

        def score(flow):
            if flow.employee_ids and employee not in flow.employee_ids:
                return None
            if flow.team_ids and employee.ff_team_id not in flow.team_ids:
                return None
            if flow.department_ids and employee.department_id not in flow.department_ids:
                return None
            return (
                3 if flow.employee_ids else 2 if flow.team_ids else 1 if flow.department_ids else 0,
                flow.min_amount,
                -flow.sequence,
            )

        scored = [(score(flow), flow) for flow in flows]
        scored = [(rank, flow) for rank, flow in scored if rank is not None]
        if not scored:
            return self.browse()
        scored.sort(key=lambda row: row[0], reverse=True)
        return scored[0][1]


class FfApprovalStep(models.Model):
    _name = 'ff.approval.step'
    _description = 'Approval Step'
    _order = 'flow_id, sequence, id'

    flow_id = fields.Many2one('ff.approval.flow', required=True, ondelete='cascade', index=True)
    sequence = fields.Integer(default=10, help='First step signs first.')
    name = fields.Char(required=True, default='Approval', translate=True)
    approver_kind = fields.Selection(APPROVER_KINDS, required=True, default='manager')
    user_id = fields.Many2one('res.users', string='Person')
    notify = fields.Boolean(string='Notify the approver', default=True)

    @api.constrains('approver_kind', 'user_id')
    def _check_person(self):
        for step in self:
            if step.approver_kind == 'user' and not step.user_id:
                raise ValidationError(self.env._('Choose the person who signs "%s".', step.name))

    def _ff_approver_for(self, employee):
        """Who signs this step for this employee. Empty means nobody could be found."""
        self.ensure_one()
        employee = employee.sudo()
        if self.approver_kind == 'user':
            return self.user_id
        if self.approver_kind == 'manager':
            return employee.parent_id.user_id
        if self.approver_kind == 'department_manager':
            return employee.department_id.manager_id.user_id
        if self.approver_kind == 'team_manager':
            team = employee.ff_team_id
            return team.manager_id.user_id if 'manager_id' in team._fields else self.env['res.users']
        return self.env['res.users']
