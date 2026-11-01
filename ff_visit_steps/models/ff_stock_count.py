from odoo import api, fields, models


class FfStockCount(models.Model):
    """Stock counted at a customer, keeping the previous count for comparison."""
    _name = 'ff.stock.count'
    _description = 'Customer Stock Count'
    _order = 'date desc, id desc'

    partner_id = fields.Many2one('res.partner', string='Contact', required=True, index=True, ondelete='cascade')
    employee_id = fields.Many2one('hr.employee', required=True, index=True, ondelete='cascade')
    visit_id = fields.Many2one('ff.visit', index=True, ondelete='set null')
    date = fields.Datetime(required=True, default=fields.Datetime.now, index=True)
    team_id = fields.Many2one(related='employee_id.ff_team_id', store=True)
    line_ids = fields.One2many('ff.stock.count.line', 'count_id', string='Products')
    item_count = fields.Integer(compute='_compute_item_count', store=True)
    note = fields.Text()

    @api.depends('line_ids')
    def _compute_item_count(self):
        for count in self:
            count.item_count = len(count.line_ids)

    @api.depends('partner_id', 'date')
    def _compute_display_name(self):
        for count in self:
            count.display_name = '%s - %s' % (count.partner_id.name or '', count.date or '')

    @api.model
    def ff_record(self, employee, partner, lines, visit=None, note=None):
        """Save a count sent from the app: [{product_id, quantity}]."""
        Product = self.env['product.product'].sudo()
        vals_list = []
        for line in lines or []:
            product = Product.browse(int(line['product_id'])).exists() \
                if str(line.get('product_id') or '').isdigit() else Product
            if not product:
                continue
            try:
                quantity = float(line.get('quantity') or 0)
            except (TypeError, ValueError):
                continue
            previous = self.env['ff.stock.count.line']._ff_previous(partner, product)
            vals_list.append({
                'product_id': product.id,
                'quantity': quantity,
                'previous_quantity': previous.quantity if previous else 0.0,
                'previous_date': previous.count_id.date if previous else False,
            })
        return self.sudo().create({
            'partner_id': partner.id,
            'employee_id': employee.id,
            'visit_id': visit.id if visit else False,
            'note': note or False,
            'line_ids': [(0, 0, vals) for vals in vals_list],
        })

    @api.model
    def ff_last_for(self, partner):
        """Most recent count of a contact."""
        return self.sudo().search([('partner_id', '=', partner.id)], limit=1)


class FfStockCountLine(models.Model):
    _name = 'ff.stock.count.line'
    _description = 'Counted Product'
    _order = 'count_id, id'

    count_id = fields.Many2one('ff.stock.count', required=True, index=True, ondelete='cascade')
    partner_id = fields.Many2one(related='count_id.partner_id', store=True, index=True)
    employee_id = fields.Many2one(related='count_id.employee_id', store=True)
    date = fields.Datetime(related='count_id.date', store=True)
    product_id = fields.Many2one('product.product', required=True, index=True, ondelete='restrict')
    uom_name = fields.Char(related='product_id.uom_id.name', string='Unit')
    quantity = fields.Float(string='Counted', digits=(16, 2))
    previous_quantity = fields.Float(string='Previous', digits=(16, 2), readonly=True)
    previous_date = fields.Datetime(string='Previous Count', readonly=True)
    delta = fields.Float(string='Difference', digits=(16, 2), compute='_compute_delta', store=True)

    @api.depends('quantity', 'previous_quantity')
    def _compute_delta(self):
        for line in self:
            line.delta = line.quantity - line.previous_quantity

    @api.model
    def _ff_previous(self, partner, product, before=None):
        """Last counted line of a product at a contact."""
        domain = [('partner_id', '=', partner.id), ('product_id', '=', product.id)]
        if before:
            domain.append(('date', '<', before))
        return self.sudo().search(domain, order='date desc, id desc', limit=1)
