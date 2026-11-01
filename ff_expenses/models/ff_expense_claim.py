from datetime import datetime, time, timedelta

from odoo import api, fields, models
from odoo.exceptions import AccessError, UserError, ValidationError

MAX_RECEIPTS = 5


def _strip_data_url(image):
    if isinstance(image, str) and image.startswith('data:') and ',' in image:
        return image.split(',', 1)[1]
    return image


class FfExpenseClaim(models.Model):
    _name = 'ff.expense.claim'
    _description = 'Field Expense Claim'
    _inherit = ['mail.thread', 'mail.activity.mixin', 'ff.numbered.mixin']
    _ff_sequence_code = 'ff.expense.claim'
    _order = 'date desc, id desc'

    name = fields.Char(compute='_compute_name', store=True)
    employee_id = fields.Many2one('hr.employee', required=True, index=True, ondelete='cascade',
                                  default=lambda self: self.env.user.employee_id)
    team_id = fields.Many2one(related='employee_id.ff_team_id', store=True)
    department_id = fields.Many2one(related='employee_id.department_id', store=True)
    date = fields.Date(required=True, index=True, default=fields.Date.context_today, tracking=True)
    kind = fields.Selection([('claim', 'Expense Claim'), ('card', 'Company Card Expense')],
                            default='claim', required=True, index=True,
                            help='A claim is paid back to the salesperson; a card expense is only recorded.')
    category_id = fields.Many2one('ff.expense.category', string='Expense Category', required=True, tracking=True,
                                  domain=[('parent_id', '=', False)])
    sub_category_id = fields.Many2one('ff.expense.category', string='Sub Category', tracking=True,
                                      domain="[('parent_id', '=', category_id)]")
    payment_mode_id = fields.Many2one('ff.expense.card', string='Payment Mode (Card)')
    amount = fields.Monetary(required=True, tracking=True)
    company_id = fields.Many2one(related='employee_id.company_id', store=True)
    currency_id = fields.Many2one(related='company_id.currency_id')
    note = fields.Text()
    partner_id = fields.Many2one('res.partner', string='Contact')
    visit_id = fields.Many2one('ff.visit', string='Visit', ondelete='set null')
    latitude = fields.Float(digits=(10, 7))
    longitude = fields.Float(digits=(10, 7))
    receipt_count = fields.Integer(compute='_compute_receipt_count')
    state = fields.Selection([
        ('draft', 'Not Sent'),
        ('submitted', 'Sent for Approval'),
        ('approved', 'Approved'),
        ('partial', 'Partly Approved'),
        ('rejected', 'Rejected'),
        ('recorded', 'Recorded'),
    ], default='draft', required=True, index=True, tracking=True)
    approved_amount = fields.Monetary(string='Approved Amount', tracking=True,
                                      help='What the approvers allow. Lower than the amount claimed makes it '
                                           'Partly Approved; a reason is then required.')
    decision_reason = fields.Char(string='Reason', tracking=True)
    sent_at = fields.Datetime(string='Sent On', readonly=True, copy=False)
    send_deadline = fields.Datetime(string='Send By', compute='_compute_send_deadline',
                                    help='A week (Mon-Sun) of claims must be sent by the next Monday 10:00 am.')
    approver_id = fields.Many2one('res.users', readonly=True, copy=False)
    decided_at = fields.Datetime(readonly=True, copy=False)
    client_uuid = fields.Char(index=True, copy=False)

    _client_uuid_uniq = models.Constraint('UNIQUE(client_uuid)', 'This claim was already received.')

    @api.depends('category_id', 'sub_category_id', 'date', 'employee_id')
    def _compute_name(self):
        for claim in self:
            kind = claim.sub_category_id.name or claim.category_id.name or ''
            claim.name = '%s - %s' % (kind, claim.date or '')

    @api.depends('date', 'employee_id', 'kind')
    def _compute_send_deadline(self):
        for claim in self:
            if claim.kind != 'claim' or not claim.date or not claim.employee_id:
                claim.send_deadline = False
                continue
            monday = claim.date - timedelta(days=claim.date.weekday()) + timedelta(days=7)
            start, _end = claim.employee_id._ff_day_bounds(monday)
            claim.send_deadline = start + timedelta(hours=10)

    def _compute_receipt_count(self):
        counts = dict(self.env['ir.attachment'].sudo()._read_group(
            [('res_model', '=', self._name), ('res_id', 'in', self.ids)], ['res_id'], ['__count']))
        for claim in self:
            claim.receipt_count = counts.get(claim.id, 0)

    @api.constrains('category_id', 'sub_category_id')
    def _check_sub_category(self):
        for claim in self:
            if claim.sub_category_id and claim.sub_category_id.parent_id != claim.category_id:
                raise ValidationError(self.env._('The sub category does not belong to %s.', claim.category_id.name))
            if claim.category_id.child_ids and not claim.sub_category_id:
                raise ValidationError(self.env._('Choose the sub category of %s.', claim.category_id.name))

    @api.constrains('amount', 'category_id')
    def _check_amount(self):
        for claim in self:
            if claim.amount <= 0:
                raise ValidationError(self.env._('The amount must be more than zero.'))
            limit = claim.category_id.max_amount
            if limit and claim.amount > limit:
                raise ValidationError(self.env._(
                    'The maximum for "%(type)s" is %(limit)s.', type=claim.category_id.name, limit=limit))

    # ------------------------------------------------------------------
    # Mobile app
    # ------------------------------------------------------------------
    @api.model
    def _ff_parse(self, employee, data):
        """The fields an expense is made of, checked, from what the app sent."""
        categories = self.env['ff.expense.category'].ff_for_employee(employee)
        category = categories.filtered(lambda c: str(c.id) == str(data.get('category_id')))
        if not category:
            raise UserError(self.env._('Choose an expense category you have access to.'))
        sub = self.env['ff.expense.category']
        if category.child_ids:
            sub = category.child_ids.filtered(lambda c: str(c.id) == str(data.get('sub_category_id')))
            if not sub:
                raise UserError(self.env._('Choose the sub category.'))
        try:
            amount = float(data.get('amount'))
        except (TypeError, ValueError):
            raise UserError(self.env._('Enter the amount.'))
        if amount <= 0:
            raise UserError(self.env._('The amount must be more than zero.'))
        day = fields.Date.to_date(data.get('date'))
        if not day:
            raise UserError(self.env._('Choose the date of the expense.'))
        return {
            'category_id': category.id, 'sub_category_id': sub.id or False, 'amount': amount, 'date': day,
            'note': (data.get('note') or '').strip() or False,
        }

    @api.model
    def _ff_attach(self, claim, receipts):
        have = self.env['ir.attachment'].sudo().search_count(
            [('res_model', '=', self._name), ('res_id', '=', claim.id)])
        receipts = [r for r in (receipts or []) if isinstance(r, str) and r]
        if have + len(receipts) > MAX_RECEIPTS:
            raise UserError(self.env._('Up to %s pictures can be added.', MAX_RECEIPTS))
        if receipts:
            self.env['ir.attachment'].sudo().create([{
                'name': 'receipt_%s_%s.jpg' % (claim.id, have + index + 1),
                'datas': _strip_data_url(receipt),
                'res_model': self._name,
                'res_id': claim.id,
                'mimetype': 'image/jpeg',
            } for index, receipt in enumerate(receipts)])

    @api.model
    def ff_create_from_app(self, employee, data):
        """Save an expense from the app. Idempotent on ``uuid``.

        An expense claim is saved as Not Sent (the picture may come later); a
        company card expense is only recorded and must carry a picture.
        """
        Claim = self.sudo()
        uuid = data.get('uuid') or False
        if uuid:
            existing = Claim.search([('client_uuid', '=', uuid)], limit=1)
            if existing:
                return existing
        kind = 'card' if data.get('kind') == 'card' else 'claim'
        if kind == 'card' and not employee.sudo().ff_expense_card_user:
            raise UserError(self.env._('Expense Submission is for company card holders. Ask the office.'))
        values = self._ff_parse(employee, data)
        category = self.env['ff.expense.category'].sudo().browse(values['category_id'])
        receipts = [r for r in (data.get('receipts') or []) if isinstance(r, str) and r][:MAX_RECEIPTS]
        mode = self.env['ff.expense.card'].sudo()
        if kind == 'card':
            mode = self.env['ff.expense.card'].sudo().browse(int(data.get('payment_mode_id') or 0)).exists()
            if not mode:
                raise UserError(self.env._('Choose the payment mode (card).'))
            if not receipts:
                raise UserError(self.env._('Add the picture of the bill.'))

        partner = self.env['res.partner'].sudo().browse(int(data['partner_id'])).exists() \
            if str(data.get('partner_id') or '').isdigit() else self.env['res.partner']
        if category.requires_client and not partner:
            raise UserError(self.env._('Choose the contact this expense belongs to.'))
        visit = self.env['ff.visit'].sudo().browse(int(data['visit_id'])).exists() \
            if str(data.get('visit_id') or '').isdigit() else self.env['ff.visit']
        if visit and visit.employee_id != employee:
            raise AccessError(self.env._('This visit is not yours.'))

        claim = Claim.create(dict(
            values,
            employee_id=employee.id, kind=kind, payment_mode_id=mode.id or False,
            state='recorded' if kind == 'card' else 'draft',
            partner_id=partner.id or (visit.partner_id.id if visit else False),
            visit_id=visit.id or False,
            latitude=data.get('lat') or 0.0, longitude=data.get('lng') or 0.0, client_uuid=uuid,
        ))
        self._ff_attach(claim, receipts)
        return claim

    def ff_update_from_app(self, employee, data):
        """Edit an expense that has not been sent."""
        self.ensure_one()
        claim = self.sudo()
        if claim.employee_id != employee:
            raise AccessError(self.env._('This expense is not yours.'))
        if claim.state != 'draft':
            raise UserError(self.env._('A sent expense cannot be edited.'))
        claim.write(self._ff_parse(employee, data))
        self._ff_attach(claim, data.get('receipts'))
        return claim

    def ff_blocker(self, employee):
        """Why this cannot be sent for approval, or an empty string."""
        self.ensure_one()
        claim = self.sudo()
        if claim.employee_id != employee:
            return self.env._('This expense is not yours.')
        if claim.kind != 'claim' or claim.state != 'draft':
            return self.env._('Only expenses that have not been sent can be sent.')
        if not claim.receipt_count:
            return self.env._('A picture is mandatory to send for approval.')
        if claim.send_deadline and fields.Datetime.now() > claim.send_deadline:
            return self.env._('The time to send this expense has passed. Ask your manager to add it.')
        return ''

    @api.model
    def ff_send_from_app(self, employee, claims):
        """Send the chosen expenses for approval, all or none."""
        problems = []
        for claim in claims:
            why = claim.ff_blocker(employee)
            if why:
                problems.append('%s: %s' % (claim.name, why))
        if problems:
            raise UserError('\n'.join(problems))
        for claim in claims.sudo():
            claim.write({'approved_amount': claim.amount, 'sent_at': fields.Datetime.now()})
            claim.action_submit()
        return claims

    # ------------------------------------------------------------------
    # Workflow
    # ------------------------------------------------------------------
    def action_submit(self):
        for claim in self.filtered(lambda c: c.state == 'draft'):
            claim.state = 'submitted'
            manager_emp = claim.employee_id.parent_id
            manager_user = manager_emp.user_id if manager_emp else False
            if manager_user:
                claim.sudo().activity_schedule('mail.mail_activity_data_todo', user_id=manager_user.id,
                                               summary=self.env._('Approve expense claim'))
            if manager_emp and 'ff.notification' in self.env:
                self.env['ff.notification'].sudo().ff_push(
                    title=self.env._('Expense to Approve'),
                    body=self.env._('%(employee)s submitted expense %(name)s for %(symbol)s%(amount).2f',
                                    employee=claim.employee_id.name,
                                    name=claim.name or '',
                                    symbol=claim.currency_id.symbol or '₹',
                                    amount=claim.amount),
                    kind='approval',
                    employee=manager_emp,
                    record=claim,
                )

    def _ff_check_approver(self):
        user = self.env.user
        if user.has_group('ff_base.group_ff_admin'):
            return
        approver = user.employee_id
        for claim in self:
            if not approver or not approver._ff_is_manager_of(claim.employee_id):
                raise AccessError(self.env._('This claim is outside your data access.'))

    def _ff_set_decision(self, approve, approver_user=False):
        for claim in self.sudo():
            if claim.state != 'submitted':
                raise UserError(self.env._('Only submitted claims can be decided.'))
            if approve:
                allowed = claim.approved_amount or claim.amount
                if allowed > claim.amount:
                    raise UserError(self.env._('The approved amount cannot be more than the amount claimed.'))
                if allowed < claim.amount and not claim.decision_reason:
                    raise UserError(self.env._('Give the reason for reducing the amount.'))
                state = 'approved' if allowed >= claim.amount else 'partial'
                claim.approved_amount = allowed
            else:
                if not claim.decision_reason:
                    raise UserError(self.env._('Give the reason for rejecting this expense.'))
                state = 'rejected'
                claim.approved_amount = 0.0
            claim.write({'state': state,
                         'approver_id': approver_user or False, 'decided_at': fields.Datetime.now()})
            if approve:
                claim._ff_assign_reference()
            claim.activity_ids.unlink()
            if 'ff.notification' in self.env and claim.employee_id:
                title = self.env._('Expense Claim Approved') if approve else self.env._('Expense Claim Rejected')
                body = self.env._('Your expense claim %(name)s for %(symbol)s%(amount).2f was %(status)s.%(note)s',
                                  name=claim.name,
                                  symbol=claim.currency_id.symbol or '₹',
                                  amount=claim.approved_amount if approve else claim.amount,
                                  status=self.env._('approved') if approve else self.env._('rejected'),
                                  note=(': ' + claim.decision_reason) if claim.decision_reason else '')
                self.env['ff.notification'].sudo().ff_push(
                    title=title, body=body, kind='decision',
                    employee=claim.employee_id, record=claim
                )

    def action_approve(self):
        self._ff_check_approver()
        self._ff_set_decision(True, self.env.uid)

    def action_reject(self):
        self._ff_check_approver()
        self._ff_set_decision(False, self.env.uid)

    def action_reset_draft(self):
        self._ff_check_approver()
        self.sudo().filtered(lambda c: c.state == 'rejected').write({'state': 'draft'})

    def _ff_store_decision(self, amount=None, reason=None):
        """What the approver decided about the amount and why, kept on the expense."""
        values = {}
        if amount is not None:
            values['approved_amount'] = float(amount)
        if reason is not None:
            values['decision_reason'] = (reason or '').strip() or False
        if values:
            self.sudo().write(values)

    def _ff_decide_as(self, employee, approve, amount=None, reason=None):
        """Approve or reject from the mobile app on behalf of ``employee``.

        The approver may lower the amount; a reason is then needed, and always to reject.
        """
        self.ensure_one()
        self._ff_store_decision(amount, reason)
        if not employee._ff_is_manager_of(self.sudo().employee_id):
            raise AccessError(self.env._('This claim is outside your data access.'))
        self._ff_set_decision(approve, employee.user_id.id)
