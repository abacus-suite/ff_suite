"""A sampling and sales event: where it is, who runs it, the stock it starts with and what each day did."""
from odoo import api, fields, models


class FfEvent(models.Model):
    _name = 'ff.event'
    _description = 'Field Event'
    _order = 'date_start desc, id desc'

    name = fields.Char(required=True)
    employee_id = fields.Many2one('hr.employee', string='Created By', required=True, index=True)
    staff_ids = fields.Many2many('hr.employee', 'ff_event_staff_rel', 'event_id', 'employee_id',
                                 string='Conducted By')
    district_id = fields.Many2one('ff.district', string='District / Territory')
    territory_id = fields.Many2one('ff.territory', string='City / Town')
    location = fields.Char()
    latitude = fields.Float(digits=(10, 7))
    longitude = fields.Float(digits=(10, 7))
    mrp = fields.Float(string='MRP', help='Kept for older events; the price category decides the MRP now.')
    price_category_id = fields.Many2one('ff.event.price.category', string='Price Category', index=True)
    completed_at = fields.Datetime(readonly=True)
    has_offer = fields.Boolean(string='Offer', default=True)
    offer_price = fields.Selection([('20', 'Rs. 20'), ('30', 'Rs. 30'), ('50', 'Rs. 50')],
                                   string='Coupon Value')
    state = fields.Selection([('draft', 'Draft'), ('running', 'Event Running'), ('on_hold', 'On Hold'),
                              ('done', 'Completed')], default='draft', required=True, index=True)
    date_start = fields.Date()
    date_end = fields.Date()
    coupons_used = fields.Integer()
    stock_ids = fields.One2many('ff.event.stock', 'event_id', string='Stock')
    day_ids = fields.One2many('ff.event.day', 'event_id', string='Days')


class FfEventStock(models.Model):
    _name = 'ff.event.stock'
    _description = 'Event Stock From a Distributor'
    _order = 'date, id'

    event_id = fields.Many2one('ff.event', required=True, ondelete='cascade', index=True)
    date = fields.Date(required=True, default=fields.Date.context_today)
    distributor_id = fields.Many2one('res.partner', string='Distributor', required=True)
    product_id = fields.Many2one('product.template', string='Flavour', required=True)
    qty = fields.Float()


class FfEventDay(models.Model):
    _name = 'ff.event.day'
    _description = 'Event Day'
    _order = 'date'

    event_id = fields.Many2one('ff.event', required=True, ondelete='cascade', index=True)
    date = fields.Date(required=True)
    captured_by_id = fields.Many2one('hr.employee', string='Captured By')
    is_final = fields.Boolean(string='End of Event')
    closing_action = fields.Selection([('stays', 'Stays at the event'), ('return', 'Returned')], default='stays')
    coupons_used = fields.Integer(string='Coupons Used')
    cash_received = fields.Float(string='Cash Received', digits=(12, 2))
    line_ids = fields.One2many('ff.event.day.line', 'day_id', string='Lines')
    return_ids = fields.One2many('ff.event.return', 'day_id', string='Returns')

    _day_uniq = models.Constraint('UNIQUE(event_id, date)', 'This event already has an entry for that day.')


class FfEventDayLine(models.Model):
    _name = 'ff.event.day.line'
    _description = 'Event Day Line'

    day_id = fields.Many2one('ff.event.day', required=True, ondelete='cascade', index=True)
    product_id = fields.Many2one('product.template', string='Flavour', required=True)
    opening = fields.Float()
    added = fields.Float()
    samples = fields.Float()
    damage = fields.Float()
    returned = fields.Float()
    closing = fields.Float()
    sold = fields.Float(compute='_compute_sold', store=True)

    @api.depends('opening', 'added', 'samples', 'damage', 'returned', 'closing')
    def _compute_sold(self):
        for line in self:
            line.sold = line.opening + line.added - line.samples - line.damage - line.returned - line.closing


class FfEventReturn(models.Model):
    _name = 'ff.event.return'
    _description = 'Event Stock Returned to a Distributor'

    day_id = fields.Many2one('ff.event.day', required=True, ondelete='cascade', index=True)
    distributor_id = fields.Many2one('res.partner', string='Distributor', required=True)
    product_id = fields.Many2one('product.template', string='Flavour', required=True)
    qty = fields.Float()


class FfEventPriceCategory(models.Model):
    """A price list for events: each flavour has its own MRP in a category (149, 179)."""
    _name = 'ff.event.price.category'
    _description = 'Event Price Category'
    _order = 'sequence, name'

    name = fields.Char(required=True)
    sequence = fields.Integer(default=10)
    line_ids = fields.One2many('ff.event.price.line', 'category_id', string='Flavour MRP', copy=True)
    active = fields.Boolean(default=True)

    _name_uniq = models.Constraint('UNIQUE(name)', 'This price category already exists.')

    def action_load_flavours(self):
        """Add every flavour that has no line yet, each at the product's own MRP (ff_mrp)."""
        templates = self.env['product.product'].sudo().ff_flavours().mapped('product_tmpl_id')
        for category in self:
            have = category.line_ids.product_id
            category.write({'line_ids': [(0, 0, {'product_id': t.id}) for t in templates - have]})
        return True


class FfEventPriceLine(models.Model):
    _name = 'ff.event.price.line'
    _description = 'Event Price Category Line'
    _order = 'category_id, product_id'

    category_id = fields.Many2one('ff.event.price.category', required=True, ondelete='cascade', index=True)
    product_id = fields.Many2one('product.template', string='Flavour', required=True)
    mrp = fields.Float(string='MRP', digits='Product Price', required=True, compute='_compute_mrp',
                       store=True, readonly=False, precompute=True,
                       help='Taken from the product MRP (ff_mrp) when the flavour is chosen; change it here for '
                            'this category.')

    _line_uniq = models.Constraint('UNIQUE(category_id, product_id)', 'A flavour has one MRP in a category.')

    @api.depends('product_id')
    def _compute_mrp(self):
        for line in self:
            # What was typed stays; a new line starts from the product's own MRP.
            if not line.mrp and line.product_id:
                template = line.product_id
                line.mrp = (template.ff_mrp if 'ff_mrp' in template._fields else 0.0) or template.list_price


class FfEventInvoice(models.Model):
    """The invoice raised to a distributor that got back more of a flavour than it supplied to the event."""
    _name = 'ff.event.invoice'
    _description = 'Event Invoice to a Distributor'

    event_id = fields.Many2one('ff.event', required=True, ondelete='cascade', index=True)
    distributor_id = fields.Many2one('res.partner', required=True)
    move_ref = fields.Integer(string='Invoice (id)', help='The draft customer invoice made in Accounting.')
    move_name = fields.Char(string='Invoice')
    quantity = fields.Float()
    amount = fields.Float(digits=(12, 2))

    _uniq = models.Constraint('UNIQUE(event_id, distributor_id)', 'An invoice was already raised.')


class FfEventDebit(models.Model):
    """The debit note asked of a distributor for the stock an event took from them."""
    _name = 'ff.event.debit'
    _description = 'Event Debit Note Request'

    event_id = fields.Many2one('ff.event', required=True, ondelete='cascade', index=True)
    distributor_id = fields.Many2one('res.partner', required=True)
    note_id = fields.Many2one('ff.distributor.note', string='Debit Note', ondelete='set null')
    quantity = fields.Float()

    _uniq = models.Constraint('UNIQUE(event_id, distributor_id)', 'A debit note was already requested.')
