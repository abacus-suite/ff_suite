from odoo import api, fields, models

PLAN_STATUSES = [
    ('planned', 'Planned'),
    ('visited', 'Visited'),
    ('missed', 'Missed'),
    ('cancelled', 'Cancelled'),
    ('skipped', 'Not Planned'),
]


class FfRoutePlanCustomer(models.Model):
    """A customer planned on a route day. Status updates itself from visits."""
    _name = 'ff.route.plan.customer'
    _description = 'Planned Customer Visit'
    _order = 'date, day_id, sequence, id'

    day_id = fields.Many2one('ff.beat.plan', string='Planned Day', required=True, index=True, ondelete='cascade')
    plan_id = fields.Many2one(related='day_id.plan_id', store=True, index=True, string='Monthly Plan')
    employee_id = fields.Many2one(related='day_id.employee_id', store=True, index=True)
    date = fields.Date(related='day_id.date', store=True, index=True)
    beat_id = fields.Many2one(related='day_id.beat_id', store=True, string='Route')
    sequence = fields.Integer(default=10)
    partner_id = fields.Many2one('res.partner', string='Customer', required=True, index=True)
    partner_category_id = fields.Many2one(related='partner_id.ff_category_id', string='Category')
    selected = fields.Boolean(string='Planned', default=True, help='Untick to leave this customer out of the day.')
    visit_id = fields.Many2one('ff.visit', ondelete='set null', readonly=True)
    cancelled = fields.Boolean()
    cancel_reason = fields.Char()
    status = fields.Selection(PLAN_STATUSES, compute='_compute_status', store=True, index=True)

    _day_partner_uniq = models.Constraint('UNIQUE(day_id, partner_id)', 'A customer appears only once per planned day.')

    @api.depends('selected', 'visit_id', 'cancelled', 'date')
    def _compute_status(self):
        today = fields.Date.context_today(self)
        for line in self:
            if not line.selected:
                line.status = 'skipped'
            elif line.visit_id:
                line.status = 'visited'
            elif line.cancelled:
                line.status = 'cancelled'
            elif line.date and line.date < today:
                line.status = 'missed'
            else:
                line.status = 'planned'

    @api.model
    def _cron_refresh_status(self):
        """Nightly: planned customers of past days that were not visited become missed."""
        lines = self.sudo().search([('status', '=', 'planned'), ('date', '<', fields.Date.context_today(self))])
        if lines:
            self.env.add_to_compute(self._fields['status'], lines)
            lines.flush_recordset(['status'])
