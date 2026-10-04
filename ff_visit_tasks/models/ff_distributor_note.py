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
    line_ids = fields.One2many('ff.distributor.note.line', 'note_id', string='Products')
    quantity_total = fields.Float(compute='_compute_total', store=True)
    company_id = fields.Many2one('res.company', required=True, default=lambda self: self.env.company)
    state = fields.Selection([('pending', 'Waiting for Approval'), ('approved', 'Approved'),
                              ('rejected', 'Rejected')], default='pending', required=True,
                             index=True, tracking=True)
    decided_by_id = fields.Many2one('res.users', readonly=True, copy=False)
    decided_at = fields.Datetime(readonly=True, copy=False)

    @api.depends('line_ids.quantity')
    def _compute_total(self):
        for note in self:
            note.quantity_total = sum(note.line_ids.mapped('quantity'))

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
        return super().create(vals_list)

    @api.model
    def ff_raise(self, employee, kind, rows, *, distributor=None, partner=None, reason=None,
                 task_log=None, demand=None):
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
        if not self.env.user.has_group('ff_base.group_ff_manager'):
            raise AccessError(self.env._('Only a manager can decide on this.'))

    def action_approve(self):
        self._ff_decide('approved')

    def action_reject(self):
        self._ff_decide('rejected')

    def _ff_decide(self, state):
        self._ff_check_decider()
        for note in self:
            if note.state != 'pending':
                raise UserError(self.env._('%s has already been decided.', note.display_name))
        self.sudo().write({'state': state, 'decided_by_id': self.env.uid,
                           'decided_at': fields.Datetime.now()})


class FfDistributorNoteLine(models.Model):
    _name = 'ff.distributor.note.line'
    _description = 'Credit / Debit Note Product'

    note_id = fields.Many2one('ff.distributor.note', required=True, ondelete='cascade', index=True)
    product_id = fields.Many2one('product.product', required=True)
    quantity = fields.Float(digits=(16, 2), required=True)
    uom_id = fields.Many2one(related='product_id.uom_id', string='Unit')
