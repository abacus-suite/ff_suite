"""Credit and debit note demands raised from the field.

Two situations, both about stock the company is answerable for but never sees:

* damaged or expired bottles at an outlet - a **credit note** demand, so the
  outlet or its distributor is made good for them;
* samples taken from a distributor's stock, or from an outlet whose distributor
  then replaces them free - a **debit note** against that distributor, who must
  not be left paying for pieces that were given away.

They are demands, not accounting entries: approval happens later, in the
office, and the field must never be stopped from recording what it found.
"""
from odoo import api, fields, models
from odoo.exceptions import AccessError, UserError


class FfDistributorNote(models.Model):
    _name = 'ff.distributor.note'
    _description = 'Credit / Debit Note Demand'
    _inherit = ['mail.thread']
    _order = 'date desc, id desc'

    name = fields.Char(default=lambda self: self.env._('New'), copy=False, readonly=True)
    kind = fields.Selection([('credit', 'Credit Note'), ('debit', 'Debit Note')],
                            required=True, index=True, tracking=True)
    distributor_id = fields.Many2one('res.partner', string='Distributor', index=True, tracking=True,
                                     domain=[('ff_is_distributor', '=', True)])
    partner_id = fields.Many2one('res.partner', string='Outlet', index=True,
                                 help='The outlet this is about, when there is one.')
    employee_id = fields.Many2one('hr.employee', string='Raised by', required=True, index=True,
                                  ondelete='cascade')
    team_id = fields.Many2one(related='employee_id.ff_team_id', store=True)
    task_log_id = fields.Many2one('ff.task.log', string='Task', ondelete='set null', index=True)
    demand_id = fields.Many2one('ff.demand', string='Free Demand', ondelete='set null',
                                help='The free-bottles demand raised with it, when there is one.')
    date = fields.Datetime(default=fields.Datetime.now, required=True, index=True)
    reason = fields.Char()
    source = fields.Selection([
        ('foc', 'Free Goods (FOC)'), ('sample', 'Samples'), ('damage', 'Damaged / Expired'),
        ('margin', 'Margin Difference'), ('other', 'Other'),
    ], string='Raised For', default='other', required=True, index=True, tracking=True)
    visit_id = fields.Many2one(related='task_log_id.visit_id', string='Visit', store=True)
    currency_id = fields.Many2one(related='company_id.currency_id')
    amount = fields.Monetary(string='Value', compute='_compute_total', store=True)
    line_ids = fields.One2many('ff.distributor.note.line', 'note_id', string='Products')
    quantity_total = fields.Float(compute='_compute_total', store=True)
    company_id = fields.Many2one('res.company', required=True, default=lambda self: self.env.company)
    state = fields.Selection([('pending', 'Waiting for Approval'), ('approved', 'Approved'),
                              ('rejected', 'Rejected')], default='pending', required=True,
                             index=True, tracking=True)
    decided_by_id = fields.Many2one('res.users', readonly=True, copy=False)
    decided_at = fields.Datetime(readonly=True, copy=False)
    move_id = fields.Many2one('account.move', string='Credit Note', readonly=True, copy=False, tracking=True)

    @api.depends('line_ids.quantity', 'line_ids.subtotal')
    def _compute_total(self):
        for note in self:
            note.quantity_total = sum(note.line_ids.mapped('quantity'))
            note.amount = sum(note.line_ids.mapped('subtotal'))

    @api.depends('name', 'distributor_id', 'partner_id')
    def _compute_display_name(self):
        for note in self:
            who = note.distributor_id.name or note.partner_id.name or ''
            note.display_name = '%s - %s' % (note.name, who)

    @api.model_create_multi
    def create(self, vals_list):
        for vals in vals_list:
            if vals.get('name', self.env._('New')) == self.env._('New'):
                code = 'ff.distributor.note.%s' % vals.get('kind', 'credit')
                vals['name'] = self.env['ir.sequence'].sudo().next_by_code(code) or '/'
        notes = super().create(vals_list)
        # The office chooses once whether notes need a manager's approval or stand on their own.
        if (self.env['ir.config_parameter'].sudo().get_param('ff_base.note_approval') or 'manual') == 'auto':
            pending = notes.filtered(lambda n: n.state == 'pending')
            pending.sudo().write({'state': 'approved', 'decided_at': fields.Datetime.now()})
            for note in pending:
                note.message_post(body=self.env._('Approved automatically.'))
                if not note.move_id and 'account.move' in self.env:
                    note._create_account_credit_note()
                note._create_dealer_stock_moves()
        if 'ff.notification' in self.env:
            for note in notes.filtered(lambda n: n.state == 'pending'):
                manager = note.employee_id.parent_id
                if manager:
                    self.env['ff.notification'].sudo().ff_push(
                        title=self.env._('Note to Approve'),
                        body=self.env._('%(who)s raised %(kind)s note %(name)s (%(symbol)s%(amount).2f)',
                                        who=note.employee_id.name,
                                        kind=note.kind,
                                        name=note.name,
                                        symbol=note.currency_id.symbol or '₹',
                                        amount=note.amount),
                        kind='approval',
                        employee=manager,
                        record=note,
                    )
        return notes

    @api.model
    def ff_raise(self, employee, kind, rows, *, distributor=None, partner=None, reason=None,
                 task_log=None, demand=None, source=None):
        """Raise a demand for a note from product rows ``[{product_id, qty}]``."""
        Product = self.env['product.product'].sudo()
        lines = []
        for row in rows or []:
            product = Product.browse(int(row.get('product_id') or 0)).exists()
            try:
                quantity = float(row.get('qty') or 0)
            except (TypeError, ValueError):
                continue
            if product and quantity > 0:
                lines.append((0, 0, {'product_id': product.id, 'quantity': quantity}))
        if not lines:
            return self.browse()
        return self.sudo().create({
            'kind': kind,
            'source': source or (('sample' if kind == 'debit' else 'damage') if task_log else 'other'),
            'company_id': employee.sudo().company_id.id,
            'distributor_id': distributor.id if distributor else False,
            'partner_id': partner.id if partner else False,
            'employee_id': employee.id,
            'reason': reason or False,
            'task_log_id': task_log.id if task_log else False,
            'demand_id': demand.id if demand else False,
            'company_id': employee.company_id.id,
            'line_ids': lines,
        })

    def _ff_check_decider(self):
        if self.env.context.get('ff_skip_decider'):
            return
        if not (self.env.user.has_group('ff_base.group_ff_manager') or self.env.user.has_group('account.group_account_user')):
            raise AccessError(self.env._('Only a manager can decide on this.'))

    def ff_decide_as(self, employee, approve):
        """A manager approves or rejects a note from the app: only for somebody in their team."""
        for note in self:
            if note.employee_id not in employee._ff_subordinates():
                raise AccessError(self.env._('This note is not from your team.'))
        records = self.with_context(ff_skip_decider=True)
        return records.action_approve() if approve else records.action_reject()

    def ff_approval_payload(self):
        self.ensure_one()
        return {
            'id': self.id, 'name': self.name, 'kind': self.kind, 'source': self.source,
            'source_label': dict(self._fields['source'].selection).get(self.source, ''),
            'employee': {'id': self.employee_id.id, 'name': self.employee_id.name},
            'distributor': {'id': self.distributor_id.id, 'name': self.distributor_id.name} if self.distributor_id else None,
            'outlet': {'id': self.partner_id.id, 'name': self.partner_id.name} if self.partner_id else None,
            'demand': self.demand_id.name or None, 'reason': self.reason or None,
            'date': self.date.isoformat() if self.date else None,
            'amount': self.amount, 'currency': self.currency_id.name, 'quantity': self.quantity_total,
            'lines': [{'product': l.product_id.display_name, 'qty': l.quantity, 'rate': l.price_unit,
                       'subtotal': l.subtotal} for l in self.line_ids],
        }

    def action_approve(self):
        self._ff_decide('approved')

    def action_reject(self):
        self._ff_decide('rejected')

    def _create_account_credit_note(self):
        self.ensure_one()
        if self.move_id or 'account.move' not in self.env:
            return self.move_id

        partner = self.distributor_id.commercial_partner_id or self.distributor_id or self.partner_id.commercial_partner_id or self.partner_id
        if not partner:
            raise UserError(self.env._('Please specify a distributor or customer for %s before approving.', self.display_name))

        lines = []
        for line in self.line_ids:
            if line.quantity <= 0:
                continue
            lines.append((0, 0, {
                'product_id': line.product_id.id,
                'quantity': line.quantity,
                'price_unit': line.price_unit,
                'product_uom_id': line.uom_id.id or line.product_id.uom_id.id,
                'name': '%s - %s' % (line.product_id.display_name, self.name),
            }))

        if not lines and self.amount:
            lines.append((0, 0, {
                'name': '%s (%s)' % (self.name, self.reason or self.source),
                'quantity': 1.0,
                'price_unit': self.amount,
            }))

        note_date = self.date.date() if self.date else fields.Date.context_today(self)
        ref_text = '%s (%s)' % (self.name, self.reason) if self.reason else self.name
        move = self.env['account.move'].sudo().with_company(self.company_id).create({
            'move_type': 'out_refund',
            'partner_id': partner.id,
            'company_id': self.company_id.id,
            'invoice_date': note_date,
            'invoice_date_due': note_date,
            'invoice_origin': self.name,
            'ref': ref_text,
            'invoice_line_ids': lines,
        })
        move.action_post()
        self.sudo().write({'move_id': move.id})
        self.message_post(body=self.env._('Posted Credit Note %s created in Accounting.') % move.name)
        return move

    def action_view_credit_note(self):
        self.ensure_one()
        return {
            'type': 'ir.actions.act_window',
            'name': self.env._('Credit Note'),
            'res_model': 'account.move',
            'res_id': self.move_id.id,
            'view_mode': 'form',
            'target': 'current',
        }

    def _create_dealer_stock_moves(self):
        self.ensure_one()
        if 'l4e.dealer.stock.move' not in self.env or not self.distributor_id:
            return
        Move = self.env['l4e.dealer.stock.move'].sudo()
        created_moves = []
        for line in self.line_ids:
            if line.quantity <= 0:
                continue
            if Move.search_count([
                ('distributor_id', '=', self.distributor_id.id),
                ('product_id', '=', line.product_id.id),
                ('reference', '=', self.name),
            ]):
                continue
            m = Move.create({
                'distributor_id': self.distributor_id.id,
                'product_id': line.product_id.id,
                'date': self.date or fields.Datetime.now(),
                'kind': 'return',
                'quantity': line.quantity,
                'reference': self.name,
                'partner_id': self.partner_id.id if self.partner_id else False,
                'company_id': self.company_id.id,
                'entered_by': self.employee_id.name or 'Credit/Debit Note',
                'note': self.reason or (dict(self._fields['source'].selection).get(self.source) if 'source' in self._fields else ''),
            })
            created_moves.append(m)
        if created_moves:
            self.message_post(body=self.env._('Stock OUT move(s) recorded in Dealer Hub for %s.') % self.distributor_id.display_name)
        return created_moves

    def action_sync_stock_moves(self):
        for note in self:
            if note.state == 'approved':
                note._create_dealer_stock_moves()
        return True

    def _ff_decide(self, state):
        self._ff_check_decider()
        for note in self:
            if note.state != 'pending':
                raise UserError(self.env._('%s has already been decided.', note.display_name))
        self.sudo().write({'state': state, 'decided_by_id': self.env.uid,
                           'decided_at': fields.Datetime.now()})
        if state == 'approved':
            for note in self:
                if not note.move_id and 'account.move' in self.env:
                    note._create_account_credit_note()
                note._create_dealer_stock_moves()
        if 'ff.notification' in self.env:
            for note in self:
                if note.employee_id:
                    self.env['ff.notification'].sudo().ff_push(
                        title=self.env._('Note Approved') if state == 'approved' else self.env._('Note Rejected'),
                        body=self.env._('%(kind)s note %(name)s was %(status)s.',
                                        kind=note.kind.capitalize(),
                                        name=note.name,
                                        status=self.env._('approved') if state == 'approved' else self.env._('rejected')),
                        kind='decision',
                        employee=note.employee_id,
                        record=note,
                    )


class FfDistributorNoteLine(models.Model):
    _name = 'ff.distributor.note.line'
    _description = 'Credit / Debit Note Product'

    note_id = fields.Many2one('ff.distributor.note', required=True, ondelete='cascade', index=True)
    product_id = fields.Many2one('product.product', required=True)
    quantity = fields.Float(digits=(16, 2), required=True)
    uom_id = fields.Many2one(related='product_id.uom_id', string='Unit')
    currency_id = fields.Many2one(related='note_id.currency_id')
    price_unit = fields.Monetary(string='Rate', help='What one unit is worth on this note.')
    subtotal = fields.Monetary(compute='_compute_subtotal', store=True)

    @api.depends('quantity', 'price_unit')
    def _compute_subtotal(self):
        for line in self:
            line.subtotal = line.quantity * line.price_unit

    @api.model_create_multi
    def create(self, vals_list):
        Note = self.env['ff.distributor.note'].sudo()
        Product = self.env['product.product'].sudo()
        for vals in vals_list:
            if vals.get('price_unit') is None and vals.get('product_id') and vals.get('note_id'):
                note = Note.browse(vals['note_id'])
                product = Product.browse(vals['product_id'])
                if note.kind == 'debit' and note.distributor_id:
                    vals['price_unit'] = product.ff_distributor_price(note.distributor_id)
                else:
                    vals['price_unit'] = product.ff_field_price(note.partner_id or None)
        return super().create(vals_list)

