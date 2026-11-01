"""Sample stock in the salesperson's hands.

Samples taken from the company, a distributor or an outlet go into the
person's hands; samples given to a lead, an outlet or any other contact come
out of them. Each movement is a row, so the balance of a person is simply the
sum of their rows, and the report can say how much was taken, how much is
still held and where the rest went.
"""
from odoo import api, fields, models


class FfSampleMove(models.Model):
    _name = 'ff.sample.move'
    _description = 'Sample Movement'
    _order = 'date desc, id desc'

    employee_id = fields.Many2one('hr.employee', required=True, index=True, ondelete='cascade')
    team_id = fields.Many2one(related='employee_id.ff_team_id', store=True)
    company_id = fields.Many2one('res.company', required=True, index=True,
                                 default=lambda self: self.env.company)
    date = fields.Datetime(required=True, default=fields.Datetime.now, index=True)
    product_id = fields.Many2one('product.product', required=True, index=True)
    direction = fields.Selection([('in', 'Taken'), ('out', 'Given')], required=True, index=True)
    quantity = fields.Float(digits=(16, 2), required=True)
    qty_in = fields.Float(string='Taken', compute='_compute_qty', store=True, digits=(16, 2))
    qty_out = fields.Float(string='Given', compute='_compute_qty', store=True, digits=(16, 2))
    balance = fields.Float(string='In Hand', compute='_compute_qty', store=True, digits=(16, 2),
                           help='Taken is plus, given is minus: summed, what the person still holds.')
    source_type = fields.Selection([('company', 'Company'), ('distributor', 'Distributor'), ('outlet', 'Outlet')],
                                   string='Taken From', index=True)
    partner_id = fields.Many2one('res.partner', string='Contact', index=True,
                                 help='Where the samples came from, or who they were given to.')
    partner_type = fields.Selection(related='partner_id.ff_category_type', store=True, string='Contact Type')
    task_log_id = fields.Many2one('ff.task.log', string='Task', ondelete='set null', index=True)

    @api.depends('direction', 'quantity')
    def _compute_qty(self):
        for move in self:
            move.qty_in = move.quantity if move.direction == 'in' else 0.0
            move.qty_out = move.quantity if move.direction == 'out' else 0.0
            move.balance = move.qty_in - move.qty_out

    @api.model
    def ff_on_hand(self, employee):
        """``[(product, quantity held)]`` for one person, products with nothing left left out."""
        groups = self.sudo()._read_group([('employee_id', '=', employee.id)], ['product_id'], ['balance:sum'])
        return [(product, qty) for product, qty in groups if abs(qty) > 1e-9]
