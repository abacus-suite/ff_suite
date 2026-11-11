# -*- coding: utf-8 -*-
import logging
from odoo import models, fields, api, _
from odoo.exceptions import UserError

_logger = logging.getLogger(__name__)


class BrewingTeaQcLineInherit(models.Model):
    _inherit = 'brewing.tea.qc.line'

    test_id = fields.Many2one(
        'qc.test.parameter',
        string='QC Test',
        domain="[('applies_to', 'in', ('all', 'brewing'))]",
        help="Select standard QC test parameter from the QC Approval Master.",
    )
    test_type = fields.Selection(
        related='test_id.test_type',
        string='Test Type',
        readonly=True,
    )
    min_value = fields.Float(
        related='test_id.min_value',
        string='Min Limit',
        readonly=True,
    )
    max_value = fields.Float(
        related='test_id.max_value',
        string='Max Limit',
        readonly=True,
    )
    unit = fields.Char(
        related='test_id.unit',
        string='Unit',
        readonly=True,
    )
    display_range = fields.Char(
        related='test_id.display_range',
        string='Target Range',
        readonly=True,
    )
    measured_value = fields.Float(
        string='Measured Value',
        digits=(6, 2),
        help="Enter the actual measured reading or test value.",
    )
    is_out_of_range = fields.Boolean(
        string='Out of Range',
        compute='_compute_is_out_of_range',
        store=True,
    )

    @api.onchange('test_id')
    def _onchange_test_id_set_details(self):
        if self.test_id:
            if not self.description:
                self.description = self.test_id.name

    @api.onchange('measured_value', 'test_id')
    def _onchange_measured_value_evaluate(self):
        if self.test_id and self.test_id.test_type == 'numeric':
            if self.test_id.min_value <= self.measured_value <= self.test_id.max_value:
                self.status = 'pass'
            else:
                self.status = 'fail'

    @api.depends('test_id', 'test_type', 'measured_value', 'status')
    def _compute_is_out_of_range(self):
        for line in self:
            if line.test_id and line.test_type == 'numeric':
                line.is_out_of_range = not (line.min_value <= line.measured_value <= line.max_value)
            else:
                line.is_out_of_range = (line.status == 'fail')


class BrewingTeaInherit(models.Model):
    _inherit = 'brewing.tea'

    approval_state = fields.Selection(
        [
            ('none', 'Normal / Passed'),
            ('to_request', 'Deviation / Approval Needed'),
            ('pending', 'Waiting QC Approval'),
            ('approved', 'Approved by QC Manager'),
            ('rejected', 'Rejected by QC Manager'),
        ],
        string='QC Approval Status',
        default='none',
        tracking=True,
        copy=False,
    )
    qc_manager_id = fields.Many2one(
        'res.users',
        string='QC Approved / Rejected By',
        readonly=True,
        copy=False,
        tracking=True,
    )
    qc_approval_date = fields.Datetime(
        string='QC Decision Date',
        readonly=True,
        copy=False,
        tracking=True,
    )
    has_qc_deviation = fields.Boolean(
        string='Has QC Deviation',
        compute='_compute_has_qc_deviation',
        store=True,
    )

    @api.depends('qc_line_ids.status', 'qc_line_ids.is_out_of_range')
    def _compute_has_qc_deviation(self):
        for rec in self:
            deviation = any(line.status == 'fail' or line.is_out_of_range for line in rec.qc_line_ids)
            rec.has_qc_deviation = deviation
            # Update approval_state if still in initial states
            if rec.approval_state in ('none', 'to_request'):
                rec.approval_state = 'to_request' if deviation else 'none'

    def action_request_qc_approval(self):
        """Submit out-of-range quality deviation to QC Manager for sign-off."""
        self.ensure_one()
        if not self.has_qc_deviation:
            raise UserError(_("No quality deviation detected for batch %s. All tests are within acceptable limits.", self.name))

        self.write({'approval_state': 'pending'})
        self.message_post(
            body=_("⚠️ <b>Quality Check Deviation:</b> Out-of-range parameters submitted to QC Manager for approval."),
            message_type='notification',
            subtype_xmlid='mail.mt_note',
        )

        # Notify QC Managers via activity
        qc_group = self.env.ref('l4e_qc_approval.group_qc_manager', raise_if_not_found=False)
        if qc_group:
            managers = qc_group.user_ids if hasattr(qc_group, 'user_ids') else getattr(qc_group, 'users', self.env['res.users'])
            root_user = self.env.ref('base.user_root', raise_if_not_found=False)
            for manager in managers:
                if root_user and manager.id == root_user.id:
                    continue
                self.activity_schedule(
                    'mail.mail_activity_data_todo',
                    user_id=manager.id,
                    summary=_("QC Deviation Approval Needed: %s", self.name),
                    note=_("Brewing batch %s has test readings outside the standard range. Please review and approve or reject.", self.name),
                )
        return True

    def action_approve_qc(self):
        """QC Manager approves out-of-range deviation."""
        self.ensure_one()
        if not self.env.user.has_group('l4e_qc_approval.group_qc_manager') and not self.env.is_admin():
            raise UserError(_("Only users in the 'QC Manager' group are authorized to approve quality deviations."))

        self.write({
            'approval_state': 'approved',
            'qc_manager_id': self.env.user.id,
            'qc_approval_date': fields.Datetime.now(),
        })
        self.message_post(
            body=_("✅ <b>Quality Deviation Approved:</b> Batch approved by QC Manager %s.", self.env.user.name),
            message_type='notification',
        )
        self.activity_feedback(['mail.mail_activity_data_todo'])
        return True

    def action_reject_qc(self):
        """QC Manager rejects out-of-range deviation."""
        self.ensure_one()
        if not self.env.user.has_group('l4e_qc_approval.group_qc_manager') and not self.env.is_admin():
            raise UserError(_("Only users in the 'QC Manager' group are authorized to reject quality deviations."))

        self.write({
            'approval_state': 'rejected',
            'qc_manager_id': self.env.user.id,
            'qc_approval_date': fields.Datetime.now(),
        })
        self.message_post(
            body=_("❌ <b>Quality Deviation Rejected:</b> Batch rejected by QC Manager %s. Transfer blocked.", self.env.user.name),
            message_type='notification',
        )
        self.activity_feedback(['mail.mail_activity_data_todo'])
        return True

    def action_reset_qc_approval(self):
        """Reset deviation approval state back to to_request."""
        self.ensure_one()
        self.write({
            'approval_state': 'to_request' if self.has_qc_deviation else 'none',
            'qc_manager_id': False,
            'qc_approval_date': False,
        })
        return True

    def action_transfer_to_fermentation(self):
        self.ensure_one()
        # Transfer permitted if QC passed OR if deviation was approved by QC Manager
        can_proceed = (self.qc_status == 'pass') or (self.approval_state == 'approved')
        if not can_proceed:
            if self.approval_state == 'pending':
                raise UserError(_("Cannot transfer to fermentation: Batch %s is currently waiting for QC Manager approval.", self.name))
            elif self.approval_state == 'rejected':
                raise UserError(_("Cannot transfer to fermentation: Quality deviation was rejected by QC Manager for batch %s.", self.name))
            else:
                raise UserError(_("Cannot transfer to fermentation: Quality Check has not passed for batch %s. Please submit for QC Manager approval.", self.name))
        return super().action_transfer_to_fermentation()
