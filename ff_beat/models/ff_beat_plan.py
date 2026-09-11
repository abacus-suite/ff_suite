from odoo import api, fields, models


class FfBeatPlan(models.Model):
    _name = 'ff.beat.plan'
    _description = 'Daily Beat Plan'
    _order = 'date desc, employee_id'

    employee_id = fields.Many2one('hr.employee', required=True, index=True, ondelete='cascade')
    team_id = fields.Many2one(related='employee_id.ff_team_id', store=True)
    beat_id = fields.Many2one('ff.beat', required=True, ondelete='restrict')
    date = fields.Date(required=True, index=True, default=fields.Date.context_today)
    visit_ids = fields.One2many('ff.visit', 'beat_plan_id', string='Visits')

    planned_count = fields.Integer(string='Planned', compute='_compute_stats', store=True)
    completed_count = fields.Integer(string='Completed', compute='_compute_stats', store=True)
    adhoc_count = fields.Integer(string='Adhoc', compute='_compute_stats', store=True)
    total_visits = fields.Integer(string='Total Visits', compute='_compute_stats', store=True)
    completion_pct = fields.Float(string='Completion %', digits=(5, 1), compute='_compute_stats', store=True)

    planned_km = fields.Float(related='beat_id.planned_km', string='Planned km')
    actual_km = fields.Float(string='Actual km', digits=(10, 1), compute='_compute_km')
    deviation_km = fields.Float(string='Deviation km', digits=(10, 1), compute='_compute_km',
                                help='Actual GPS distance minus planned route distance.')
    status = fields.Selection([
        ('planned', 'Planned'),
        ('in_progress', 'In Progress'),
        ('done', 'Completed'),
        ('missed', 'Missed'),
    ], compute='_compute_status')

    _employee_date_uniq = models.Constraint('UNIQUE(employee_id, date)', 'An employee has one beat plan per day.')

    @api.depends('employee_id', 'beat_id', 'date')
    def _compute_display_name(self):
        for plan in self:
            plan.display_name = '%s - %s (%s)' % (plan.employee_id.name or '', plan.beat_id.name or '', plan.date or '')

    @api.depends('beat_id.line_ids.partner_id', 'visit_ids.state', 'visit_ids.partner_id')
    def _compute_stats(self):
        for plan in self:
            planned = plan.beat_id.line_ids.partner_id
            done = plan.visit_ids.filtered(lambda v: v.state == 'done').partner_id
            plan.planned_count = len(planned)
            plan.completed_count = len(done & planned)
            plan.adhoc_count = len(plan.visit_ids.partner_id - planned)
            plan.total_visits = len(plan.visit_ids)
            plan.completion_pct = 100.0 * plan.completed_count / len(planned) if planned else 0.0

    def _compute_km(self):
        tracks = {(t.employee_id.id, t.date): t.distance_km for t in self.env['ff.daily.track'].sudo().search([
            ('employee_id', 'in', self.employee_id.ids), ('date', 'in', self.mapped('date')),
        ])}
        for plan in self:
            plan.actual_km = tracks.get((plan.employee_id.id, plan.date), 0.0)
            plan.deviation_km = plan.actual_km - plan.planned_km if plan.actual_km else 0.0

    def _compute_status(self):
        today = fields.Date.context_today(self)
        for plan in self:
            if plan.planned_count and plan.completed_count >= plan.planned_count:
                plan.status = 'done'
            elif plan.total_visits:
                plan.status = 'in_progress'
            elif plan.date and plan.date < today:
                plan.status = 'missed'
            else:
                plan.status = 'planned'
