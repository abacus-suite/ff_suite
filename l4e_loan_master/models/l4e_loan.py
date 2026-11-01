# -*- coding: utf-8 -*-
from dateutil.relativedelta import relativedelta
from odoo import api, fields, models, _
from odoo.exceptions import UserError, ValidationError


class L4eLoan(models.Model):
    _name = 'l4e.loan'
    _description = 'Employee Loan & Advance Master'
    _inherit = ['mail.thread', 'mail.activity.mixin']
    _order = 'create_date desc, id desc'

    name = fields.Char(
        string='Loan Reference',
        required=True,
        copy=False,
        readonly=True,
        default=lambda self: self.env._('New'),
        index=True,
    )
    employee_id = fields.Many2one(
        'hr.employee',
        string='Employee',
        required=True,
        tracking=True,
        index=True,
    )
    department_id = fields.Many2one(
        'hr.department',
        related='employee_id.department_id',
        string='Department',
        store=True,
        readonly=True,
    )
    job_id = fields.Many2one(
        'hr.job',
        related='employee_id.job_id',
        string='Job Position',
        store=True,
        readonly=True,
    )
    company_id = fields.Many2one(
        'res.company',
        string='Company',
        required=True,
        default=lambda self: self.env.company,
    )
    currency_id = fields.Many2one(
        'res.currency',
        related='company_id.currency_id',
        string='Currency',
    )
    loan_type_id = fields.Many2one(
        'l4e.loan.type',
        string='Loan Policy / Type',
        required=True,
        tracking=True,
    )
    loan_amount = fields.Monetary(
        string='Principal Sanctioned (₹)',
        required=True,
        tracking=True,
        help='Total sanctioned loan / advance amount in ₹.',
    )
    installment_count = fields.Integer(
        string='Tenure (Months)',
        default=1,
        required=True,
        tracking=True,
        help='Number of monthly repayment installments.',
    )
    monthly_amount = fields.Monetary(
        string='Monthly Installment (₹)',
        compute='_compute_monthly_amount',
        store=True,
        readonly=False,
        help='Calculated monthly recovery amount.',
    )
    disbursement_date = fields.Date(
        string='Disbursement Date',
        default=fields.Date.context_today,
        tracking=True,
        help='Date when funds were paid out to the employee.',
    )
    start_date = fields.Date(
        string='Deduction Start Month',
        default=fields.Date.context_today,
        required=True,
        tracking=True,
        help='First salary deduction month.',
    )

    # -------------------------------------------------------------
    # Historical / Opening Loan Migration (Feature 1)
    # -------------------------------------------------------------
    is_historical = fields.Boolean(
        string='Is Historical / Opening Loan',
        default=False,
        tracking=True,
        help='Check if this loan originated before Odoo go-live (e.g. Tally / Excel records) with existing recovery history.',
    )
    historical_recovered = fields.Monetary(
        string='Past Amount Already Recovered (₹)',
        default=0.0,
        tracking=True,
        help='Amount already deducted/recovered in previous systems before Odoo.',
    )
    opening_balance = fields.Monetary(
        string='Opening Balance in Odoo (₹)',
        compute='_compute_opening_balance',
        store=True,
        help='Remaining principal to be amortized and recovered through Odoo.',
    )

    # -------------------------------------------------------------
    # Balances & Recovery Progress
    # -------------------------------------------------------------
    total_paid = fields.Monetary(
        string='Total Recovered (₹)',
        compute='_compute_loan_amounts',
        store=True,
        help='Sum of all paid installments plus past historical recovery.',
    )
    balance_amount = fields.Monetary(
        string='Remaining Balance (₹)',
        compute='_compute_loan_amounts',
        store=True,
        help='Outstanding balance left to recover.',
    )
    overdue_count = fields.Integer(
        string='Overdue / Skipped Months (OD)',
        compute='_compute_loan_amounts',
        store=True,
        help='Count of installments that were missed or skipped.',
    )
    paid_installment_count = fields.Integer(
        string='Paid Installments Count',
        compute='_compute_loan_amounts',
        store=True,
    )
    progress_percentage = fields.Float(
        string='Repayment Progress %',
        compute='_compute_loan_amounts',
        store=True,
    )

    state = fields.Selection([
        ('draft', 'Draft'),
        ('submitted', 'Waiting Approval'),
        ('approved', 'Approved'),
        ('disbursed', 'Active / Disbursed'),
        ('closed', 'Closed'),
        ('refused', 'Refused'),
    ], string='Status', default='draft', required=True, tracking=True, index=True)

    installment_ids = fields.One2many(
        'l4e.loan.installment',
        'loan_id',
        string='Repayment Schedule',
        copy=False,
    )
    reason = fields.Text(string='Reason / Purpose for Loan')

    # Approval stamps
    approved_by_id = fields.Many2one('res.users', string='Approved By', readonly=True, copy=False)
    approved_date = fields.Datetime(string='Approved On', readonly=True, copy=False)
    disbursed_by_id = fields.Many2one('res.users', string='Disbursed By', readonly=True, copy=False)
    disbursed_date = fields.Datetime(string='Disbursed On', readonly=True, copy=False)
    closed_date = fields.Datetime(string='Closed On', readonly=True, copy=False)
    refusal_reason = fields.Text(string='Refusal Reason', readonly=True, copy=False)

    # -------------------------------------------------------------
    # Employee Lifetime Credit Track Record (Feature 2 & 3)
    # -------------------------------------------------------------
    employee_lifetime_loan_count = fields.Integer(
        string='Lifetime Loans Availed',
        compute='_compute_employee_track_record',
    )
    employee_lifetime_loan_amount = fields.Monetary(
        string='Lifetime Sanctioned Amount',
        compute='_compute_employee_track_record',
    )
    employee_lifetime_repaid_amount = fields.Monetary(
        string='Lifetime Repaid Amount',
        compute='_compute_employee_track_record',
    )
    employee_active_exposure = fields.Monetary(
        string='Current Active Exposure',
        compute='_compute_employee_track_record',
    )
    employee_overdue_count = fields.Integer(
        string='Lifetime Overdue (OD) Count',
        compute='_compute_employee_track_record',
    )
    employee_credit_standing = fields.Selection([
        ('excellent', '🟢 Excellent (100% On-Time Clearance)'),
        ('fair', '🟡 Moderate Exposure'),
        ('risk', '🔴 High Risk / Past Overdue Defaults'),
    ], string='Credit Standing', compute='_compute_employee_track_record')

    # -------------------------------------------------------------
    # Constraints & Computes
    # -------------------------------------------------------------
    @api.constrains('loan_amount', 'installment_count', 'historical_recovered')
    def _check_loan_parameters(self):
        for rec in self:
            if rec.loan_amount <= 0:
                raise ValidationError(_("Loan principal amount must be greater than zero."))
            if rec.installment_count <= 0:
                raise ValidationError(_("Tenure must be at least 1 month."))
            if rec.is_historical and rec.historical_recovered > rec.loan_amount:
                raise ValidationError(_("Historical recovered amount cannot exceed total loan amount."))
            if rec.loan_type_id:
                if rec.loan_type_id.max_amount > 0 and rec.loan_amount > rec.loan_type_id.max_amount:
                    raise ValidationError(_(
                        "Loan amount ₹ %s exceeds the maximum policy limit of ₹ %s for %s."
                    ) % (
                        "{:,.2f}".format(rec.loan_amount),
                        "{:,.2f}".format(rec.loan_type_id.max_amount),
                        rec.loan_type_id.name
                    ))
                if rec.loan_type_id.max_installments > 0 and rec.installment_count > rec.loan_type_id.max_installments:
                    raise ValidationError(_(
                        "Tenure of %d months exceeds the maximum allowed tenure of %d months for %s."
                    ) % (
                        rec.installment_count,
                        rec.loan_type_id.max_installments,
                        rec.loan_type_id.name
                    ))

    @api.depends('loan_amount', 'installment_count', 'is_historical', 'historical_recovered')
    def _compute_monthly_amount(self):
        for rec in self:
            principal = (rec.loan_amount - rec.historical_recovered) if rec.is_historical else rec.loan_amount
            if rec.installment_count > 0 and principal > 0:
                rec.monthly_amount = round(principal / rec.installment_count, 2)
            else:
                rec.monthly_amount = 0.0

    @api.depends('loan_amount', 'historical_recovered', 'is_historical')
    def _compute_opening_balance(self):
        for rec in self:
            if rec.is_historical:
                rec.opening_balance = max(0.0, rec.loan_amount - rec.historical_recovered)
            else:
                rec.opening_balance = rec.loan_amount

    @api.depends('loan_amount', 'historical_recovered', 'is_historical',
                 'installment_ids.amount', 'installment_ids.state')
    def _compute_loan_amounts(self):
        for rec in self:
            paid_lines = rec.installment_ids.filtered(lambda l: l.state == 'paid')
            paid_from_schedule = sum(paid_lines.mapped('amount'))
            past_paid = rec.historical_recovered if rec.is_historical else 0.0
            total_repaid = paid_from_schedule + past_paid

            rec.total_paid = total_repaid
            rec.balance_amount = max(0.0, rec.loan_amount - total_repaid)
            rec.paid_installment_count = len(paid_lines)
            rec.overdue_count = len(rec.installment_ids.filtered(lambda l: l.state == 'overdue'))
            rec.progress_percentage = round((total_repaid / rec.loan_amount * 100.0), 1) if rec.loan_amount > 0 else 0.0

    @api.depends('employee_id')
    def _compute_employee_track_record(self):
        for rec in self:
            if not rec.employee_id:
                rec.employee_lifetime_loan_count = 0
                rec.employee_lifetime_loan_amount = 0.0
                rec.employee_lifetime_repaid_amount = 0.0
                rec.employee_active_exposure = 0.0
                rec.employee_overdue_count = 0
                rec.employee_credit_standing = 'excellent'
                continue

            all_loans = self.search([
                ('employee_id', '=', rec.employee_id.id),
                ('id', '!=', rec.id if isinstance(rec.id, int) else 0),
                ('state', 'in', ('disbursed', 'closed')),
            ])
            rec.employee_lifetime_loan_count = len(all_loans)
            rec.employee_lifetime_loan_amount = sum(all_loans.mapped('loan_amount'))
            rec.employee_lifetime_repaid_amount = sum(all_loans.mapped('total_paid'))

            active_loans = all_loans.filtered(lambda l: l.state == 'disbursed')
            rec.employee_active_exposure = sum(active_loans.mapped('balance_amount'))
            
            overdue_lines = self.env['l4e.loan.installment'].search_count([
                ('employee_id', '=', rec.employee_id.id),
                ('state', '=', 'overdue'),
            ])
            rec.employee_overdue_count = overdue_lines

            if overdue_lines > 0:
                rec.employee_credit_standing = 'risk'
            elif rec.employee_active_exposure > 50000.0:
                rec.employee_credit_standing = 'fair'
            else:
                rec.employee_credit_standing = 'excellent'

    # -------------------------------------------------------------
    # ORM Overrides
    # -------------------------------------------------------------
    @api.model_create_multi
    def create(self, vals_list):
        for vals in vals_list:
            if vals.get('name', _('New')) == _('New'):
                vals['name'] = self.env['ir.sequence'].next_by_code('l4e.loan') or _('New')
        return super().create(vals_list)

    def write(self, vals):
        res = super().write(vals)
        for rec in self:
            rec._check_auto_close()
        return res

    # -------------------------------------------------------------
    # Business Actions
    # -------------------------------------------------------------
    def action_compute_schedule(self):
        """Generate date-wise monthly amortization installment rows."""
        self.ensure_one()
        if self.state not in ('draft', 'submitted'):
            raise UserError(_("Installment schedule can only be computed in Draft or Submitted stage."))

        principal = self.opening_balance if self.is_historical else self.loan_amount
        if principal <= 0:
            raise UserError(_("Principal amount must be greater than zero to generate a schedule."))
        if self.installment_count <= 0:
            raise UserError(_("Tenure months must be at least 1."))
        if not self.start_date:
            raise UserError(_("Please specify the deduction start date."))

        # Clear existing un-paid lines
        self.installment_ids.filtered(lambda l: l.state != 'paid').unlink()

        monthly = round(principal / self.installment_count, 2)
        accumulated = 0.0
        lines = []

        for i in range(self.installment_count):
            due_date = self.start_date + relativedelta(months=i)
            # Adjust rounding difference on the last installment
            if i == self.installment_count - 1:
                amt = round(principal - accumulated, 2)
            else:
                amt = monthly
                accumulated += amt

            lines.append((0, 0, {
                'name': _("Installment #%d") % (i + 1),
                'sequence': (i + 1) * 10,
                'date': due_date,
                'amount': amt,
                'state': 'pending',
            }))

        self.installment_ids = lines
        return True

    def action_submit(self):
        self.ensure_one()
        if not self.installment_ids:
            self.action_compute_schedule()
        self.write({'state': 'submitted'})
        self.message_post(body=_("<b>Loan Application Submitted:</b> ₹ %s for %d months.") % (
            "{:,.2f}".format(self.loan_amount), self.installment_count
        ))
        return True

    def action_approve(self):
        self.ensure_one()
        self.write({
            'state': 'approved',
            'approved_by_id': self.env.user.id,
            'approved_date': fields.Datetime.now(),
        })
        self.message_post(body=_("<b>Loan Approved</b> by %s.") % self.env.user.name)
        return True

    def action_disburse(self):
        self.ensure_one()
        if not self.installment_ids:
            self.action_compute_schedule()
        self.write({
            'state': 'disbursed',
            'disbursed_by_id': self.env.user.id,
            'disbursed_date': fields.Datetime.now(),
            'disbursement_date': self.disbursement_date or fields.Date.context_today(self),
        })
        self.message_post(body=_("<b>Loan Disbursed / Activated:</b> Ready for monthly salary recovery."))
        return True

    def action_activate_historical(self):
        """Fast-track activation for pre-existing legacy loans from Tally/Excel."""
        self.ensure_one()
        if not self.is_historical:
            raise UserError(_("This action is only applicable for Historical / Opening loans."))
        if not self.installment_ids:
            self.action_compute_schedule()
        self.write({
            'state': 'disbursed',
            'disbursed_by_id': self.env.user.id,
            'disbursed_date': fields.Datetime.now(),
        })
        self.message_post(body=_(
            "<b>Historical Opening Loan Activated:</b> Original Principal: ₹ %s, Past Recovered: ₹ %s, Remaining in Odoo: ₹ %s."
        ) % (
            "{:,.2f}".format(self.loan_amount),
            "{:,.2f}".format(self.historical_recovered),
            "{:,.2f}".format(self.opening_balance)
        ))
        return True

    def action_refuse(self):
        self.ensure_one()
        self.write({'state': 'refused'})
        self.message_post(body=_("<b>Loan Application Refused</b> by %s.") % self.env.user.name)
        return True

    def action_reset_to_draft(self):
        self.ensure_one()
        if any(l.state == 'paid' for l in self.installment_ids):
            raise UserError(_("Cannot reset to draft: Some installments have already been marked as paid."))
        self.write({'state': 'draft'})
        return True

    def _check_auto_close(self):
        """Automatically switch state to 'closed' when balance is zero."""
        for rec in self:
            if rec.state == 'disbursed' and rec.balance_amount <= 0.01 and rec.installment_ids:
                all_paid = all(l.state == 'paid' for l in rec.installment_ids)
                if all_paid or rec.balance_amount <= 0.01:
                    rec.write({
                        'state': 'closed',
                        'closed_date': fields.Datetime.now(),
                    })
                    rec.message_post(body=_(
                        "<b>🎉 Loan Fully Cleared:</b> Balance has reached ₹ 0.00. Loan is now Closed."
                    ))

    def action_open_settle_wizard(self):
        """Open popup wizard to pre-close/settle remaining loan balance early."""
        self.ensure_one()
        return {
            'name': _("Pre-close / Settle Loan"),
            'type': 'ir.actions.act_window',
            'res_model': 'l4e.loan.settle.wizard',
            'view_mode': 'form',
            'target': 'new',
            'context': {
                'default_loan_id': self.id,
                'default_settlement_amount': self.balance_amount,
            },
        }
