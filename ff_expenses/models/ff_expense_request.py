"""Expense Payment Request: the company pays the vendor directly, against a tax invoice or a quotation.

With a tax invoice accounts pay and the request is complete. With a quotation accounts pay and set the date by
which the tax invoice must come; the request is complete only once the salesperson uploads that tax invoice,
and is reminded every day until then.
"""
from datetime import timedelta

from odoo import api, fields, models
from odoo.exceptions import UserError

from .ff_expense_claim import _strip_data_url

STATES = [
    ('requested', 'With accounts'),
    ('invoice_pending', 'Invoice pending'),
    ('completed', 'Completed'),
    ('rejected', 'Rejected'),
]


class FfExpenseRequest(models.Model):
    _name = 'ff.expense.request'
    _description = 'Expense Payment Request'
    _inherit = ['mail.thread']
    _order = 'date desc, id desc'

    name = fields.Char(compute='_compute_name', store=True)
    employee_id = fields.Many2one('hr.employee', required=True, index=True, ondelete='cascade')
    date = fields.Date(required=True, index=True, default=fields.Date.context_today, tracking=True)
    category_id = fields.Many2one('ff.expense.category', string='Expense Category', required=True, tracking=True,
                                  domain=[('parent_id', '=', False)])
    sub_category_id = fields.Many2one('ff.expense.category', string='Sub Category', tracking=True)
    amount = fields.Monetary(required=True, tracking=True)
    document = fields.Selection([('tax_invoice', 'Tax invoice'), ('quotation', 'Quotation')],
                                required=True, default='quotation', tracking=True)
    state = fields.Selection(STATES, default='requested', required=True, index=True, tracking=True)
    paid_on = fields.Date(readonly=True, copy=False, tracking=True)
    invoice_due = fields.Date(string='Tax Invoice Due', copy=False, tracking=True,
                              help='For a quotation: the date by which the tax invoice must be uploaded.')
    reject_reason = fields.Text(copy=False)
    note = fields.Text()
    last_reminder = fields.Date(readonly=True, copy=False)
    company_id = fields.Many2one(related='employee_id.company_id', store=True)
    currency_id = fields.Many2one(related='company_id.currency_id')
    client_uuid = fields.Char(copy=False, index=True)
    attachment_count = fields.Integer(string='Documents', compute='_compute_attachment_count')

    _uuid_uniq = models.Constraint('UNIQUE(client_uuid)', 'This request was already sent.')

    @api.depends('employee_id.name', 'category_id.name', 'date')
    def _compute_name(self):
        for rec in self:
            rec.name = '%s - %s' % (rec.employee_id.name or '', rec.category_id.name or '')

    def _compute_attachment_count(self):
        counts = dict(self.env['ir.attachment'].sudo()._read_group(
            [('res_model', '=', self._name), ('res_id', 'in', self.ids)], ['res_id'], ['__count']))
        for rec in self:
            rec.attachment_count = counts.get(rec.id, 0)

    def action_view_documents(self):
        self.ensure_one()
        return {
            'type': 'ir.actions.act_window', 'name': self.env._('Documents'), 'res_model': 'ir.attachment',
            'view_mode': 'kanban,list,form',
            'domain': [('res_model', '=', self._name), ('res_id', '=', self.id)],
            'context': {'default_res_model': self._name, 'default_res_id': self.id},
        }

    # ------------------------------------------------------------------
    def _ff_attach(self, photo, label):
        self.ensure_one()
        photo = _strip_data_url(photo)
        if not photo:
            raise UserError(self.env._('A photo of the %s is needed.', label))
        self.env['ir.attachment'].sudo().create({
            'name': '%s_%s.jpg' % (label.replace(' ', '_'), self.id),
            'datas': photo, 'res_model': self._name, 'res_id': self.id, 'mimetype': 'image/jpeg',
        })

    def _ff_notify(self, title, body):
        if 'ff.notification' in self.env:
            for rec in self:
                self.env['ff.notification'].sudo().ff_push(
                    title=title, body=body, kind='decision', employee=rec.employee_id, record=rec)

    # ------------------------------------------------------------------ accounts
    def action_mark_paid(self):
        """Accounts have paid the vendor. A quotation then waits for the tax invoice, by the due date set."""
        for rec in self:
            if rec.state != 'requested':
                raise UserError(self.env._('%s is not waiting for payment.', rec.name))
            if rec.document == 'quotation':
                due = rec.invoice_due or fields.Date.context_today(rec) + timedelta(days=7)
                rec.write({'state': 'invoice_pending', 'paid_on': fields.Date.context_today(rec),
                           'invoice_due': due})
                rec._ff_notify(
                    self.env._('Payment Request Paid'),
                    self.env._('%(name)s was paid. Upload the tax invoice by %(due)s.', name=rec.name, due=due))
            else:
                rec.write({'state': 'completed', 'paid_on': fields.Date.context_today(rec)})
                rec._ff_notify(self.env._('Payment Request Paid'), self.env._('%s was paid.', rec.name))

    def action_reject(self):
        for rec in self:
            if rec.state != 'requested':
                raise UserError(self.env._('%s is not waiting for payment.', rec.name))
            rec.write({'state': 'rejected'})
            rec._ff_notify(self.env._('Payment Request Rejected'),
                           self.env._('%(name)s was rejected%(why)s.', name=rec.name,
                                      why=(': ' + rec.reject_reason) if rec.reject_reason else ''))

    def action_reset(self):
        self.filtered(lambda r: r.state == 'rejected').write({'state': 'requested'})

    # ------------------------------------------------------------------ salesperson
    def ff_upload_invoice(self, photo):
        """The tax invoice for a quotation that was paid: this completes the request."""
        self.ensure_one()
        if self.state != 'invoice_pending':
            raise UserError(self.env._('This request is not waiting for a tax invoice.'))
        self._ff_attach(photo, 'tax invoice')
        self.write({'state': 'completed'})
        return self

    @api.model
    def _cron_remind(self):
        """Every day, until the tax invoice is uploaded: remind whoever still owes one."""
        today = fields.Date.context_today(self)
        pending = self.sudo().search([
            ('state', '=', 'invoice_pending'), '|', ('last_reminder', '=', False), ('last_reminder', '<', today)])
        for rec in pending:
            late = rec.invoice_due and rec.invoice_due < today
            rec._ff_notify(
                self.env._('Tax Invoice Pending'),
                self.env._('Upload the tax invoice of %(name)s%(when)s.', name=rec.name,
                           when=(' (it was due on %s)' % rec.invoice_due) if late
                           else (' by %s' % rec.invoice_due if rec.invoice_due else '')))
            rec.last_reminder = today
