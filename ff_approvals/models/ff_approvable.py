"""The chain a document walks while it is being approved.

A document copies the flow's steps when it is submitted, so it keeps the rule
that applied on the day. Each line waits for its approver; the last approval
decides the document, and any rejection ends it there.
"""
from odoo import api, fields, models
from odoo.exceptions import AccessError, UserError

LINE_STATES = [
    ('pending', 'Waiting'),
    ('approved', 'Approved'),
    ('rejected', 'Rejected'),
    ('skipped', 'Skipped'),
]


class FfApprovalLine(models.Model):
    _name = 'ff.approval.line'
    _description = 'Approval Step of a Document'
    _order = 'res_model, res_id, sequence, id'

    res_model = fields.Char(required=True, index=True)
    res_id = fields.Integer(required=True, index=True)
    document_name = fields.Char()
    employee_id = fields.Many2one('hr.employee', string='Claimed by', index=True, ondelete='cascade')
    sequence = fields.Integer(default=10)
    name = fields.Char(required=True)
    user_id = fields.Many2one('res.users', string='Approver', index=True)
    state = fields.Selection(LINE_STATES, default='pending', required=True, index=True)
    decided_at = fields.Datetime(readonly=True)
    note = fields.Char()

    def _ff_document(self):
        self.ensure_one()
        return self.env[self.res_model].browse(self.res_id).exists()


class FfApprovable(models.AbstractModel):
    """Mix into any document that needs more than one signature."""
    _name = 'ff.approvable.mixin'
    _description = 'Multi-step Approval'

    approval_line_ids = fields.One2many('ff.approval.line', 'res_id', string='Approvals',
                                        domain=lambda self: [('res_model', '=', self._name)],
                                        auto_join=True)
    approval_step = fields.Integer(string='Step', default=0, copy=False)
    approval_total = fields.Integer(compute='_compute_approval', string='Steps')
    approver_user_id = fields.Many2one('res.users', compute='_compute_approval', string='Waiting for',
                                       help='Who the document is waiting for right now.')

    @api.depends('approval_line_ids.state', 'approval_line_ids.user_id')
    def _compute_approval(self):
        for record in self:
            lines = record.approval_line_ids.sorted('sequence')
            record.approval_total = len(lines)
            pending = lines.filtered(lambda line: line.state == 'pending')
            record.approver_user_id = pending[:1].user_id

    # ------------------------------------------------------------------
    def _ff_start_approval(self):
        """Copy the flow onto the document. Returns True when a chain exists."""
        self.ensure_one()
        self.approval_line_ids.unlink()
        flow = self.env['ff.approval.flow'].ff_flow_for(self)
        if not flow:
            return False
        Line = self.env['ff.approval.line'].sudo()
        created = Line.browse()
        for step in flow.step_ids.sorted('sequence'):
            approver = step._ff_approver_for(self.employee_id)
            created |= Line.create({
                'res_model': self._name,
                'res_id': self.id,
                'document_name': self.display_name,
                'employee_id': self.employee_id.id,
                'sequence': step.sequence,
                'name': step.name,
                'user_id': approver.id or False,
                # A step nobody can be found for is skipped rather than
                # stranding the document forever.
                'state': 'pending' if approver else 'skipped',
            })
        self.approval_step = 0
        waiting = created.filtered(lambda line: line.state == 'pending')[:1]
        if not waiting:
            return False  # nobody to ask: fall back to the plain approval
        self._ff_notify_approver(waiting)
        return True

    def _ff_decide_step(self, user, approve, note=''):
        """Record one person's decision and move the document on."""
        self.ensure_one()
        line = self.approval_line_ids.sorted('sequence').filtered(
            lambda row: row.state == 'pending')[:1]
        if not line:
            raise UserError(self.env._('This document is not waiting for an approval.'))
        if line.user_id != user and not user.has_group('ff_base.group_ff_admin'):
            raise AccessError(self.env._('%s is waiting for %s.', self.display_name, line.user_id.name))
        line.sudo().write({
            'state': 'approved' if approve else 'rejected',
            'decided_at': fields.Datetime.now(),
            'note': note or False,
        })
        if not approve:
            self.sudo().approval_line_ids.filtered(lambda row: row.state == 'pending').write(
                {'state': 'skipped'})
            self._ff_finish_approval(False, user, note)
            return False
        nxt = self.approval_line_ids.sorted('sequence').filtered(
            lambda row: row.state == 'pending')[:1]
        if nxt:
            self.approval_step += 1
            self._ff_notify_approver(nxt)
            return True
        self._ff_finish_approval(True, user, note)
        return False

    # -- what each document does at the end; overridden where needed -----
    def _ff_finish_approval(self, approved, user, note=''):
        self.ensure_one()
        self._ff_set_decision(approved, user.id)
        self._ff_notify_owner(approved, note)

    # -- telling people ---------------------------------------------------
    def _ff_notify_approver(self, line):
        """Ask the next person, in Odoo and on their phone."""
        self.ensure_one()
        if not line.user_id:
            return
        body = self.env._('%(document)s from %(employee)s is waiting for your approval.',
                          document=self.display_name, employee=self.employee_id.name)
        self.sudo().message_post(body=body, partner_ids=line.user_id.partner_id.ids)
        self.env['ff.notification'].sudo().ff_push(
            user=line.user_id,
            title=self.env._('Approval needed'),
            body=body,
            kind='approval',
            record=self,
        )

    def _ff_notify_owner(self, approved, note=''):
        """Tell the person who claimed, either way."""
        self.ensure_one()
        employee = self.employee_id
        body = (self.env._('%s was approved.', self.display_name) if approved
                else self.env._('%s was rejected.', self.display_name))
        if note:
            body = '%s %s' % (body, note)
        if employee.user_id:
            self.sudo().message_post(body=body, partner_ids=employee.user_id.partner_id.ids)
        self.env['ff.notification'].sudo().ff_push(
            employee=employee,
            title=self.env._('Approved') if approved else self.env._('Rejected'),
            body=body,
            kind='decision',
            record=self,
        )
