from odoo import api, fields, models
from odoo.exceptions import ValidationError


class FfContactAccessRequest(models.Model):
    """A dated request for contacts outside one's own list."""
    _name = 'ff.contact.access.request'
    _description = 'Contact Access Request'
    _order = 'id desc'

    employee_id = fields.Many2one('hr.employee', required=True, index=True, ondelete='cascade')
    scope_type = fields.Selection([('territory', 'Territory'), ('beat', 'Beat'), ('city', 'City')],
                                  required=True, default='beat')
    territory_id = fields.Many2one('ff.territory')
    beat_id = fields.Many2one('ff.beat')
    district_id = fields.Many2one('ff.district', string='City / District')
    date_from = fields.Date(required=True, default=fields.Date.context_today)
    date_to = fields.Date(required=True)
    reason = fields.Text()
    state = fields.Selection([('pending', 'Waiting'), ('approved', 'Approved'), ('rejected', 'Turned down')],
                             default='pending', required=True, index=True)
    status = fields.Selection([
        ('pending', 'Waiting'), ('upcoming', 'Starts later'), ('active', 'Active'),
        ('expired', 'Expired'), ('rejected', 'Turned down')], compute='_compute_status')
    decided_by_id = fields.Many2one('hr.employee', readonly=True)
    decided_at = fields.Datetime(readonly=True)
    decision_note = fields.Char()
    target = fields.Char(compute='_compute_target')

    @api.constrains('date_from', 'date_to', 'scope_type', 'territory_id', 'beat_id', 'district_id')
    def _check_request(self):
        for rec in self:
            if rec.date_to < rec.date_from:
                raise ValidationError(self.env._('The to date cannot be before the from date.'))
            field = {'territory': 'territory_id', 'beat': 'beat_id', 'city': 'district_id'}[rec.scope_type]
            if not rec[field]:
                raise ValidationError(self.env._('Choose the %s you need.', rec.scope_type))

    @api.depends('scope_type', 'territory_id', 'beat_id', 'district_id')
    def _compute_target(self):
        for rec in self:
            record = (rec.territory_id if rec.scope_type == 'territory' else
                      rec.beat_id if rec.scope_type == 'beat' else rec.district_id)
            rec.target = record.display_name or ''

    @api.depends('state', 'date_from', 'date_to')
    def _compute_status(self):
        today = fields.Date.context_today(self)
        for rec in self:
            if rec.state != 'approved':
                rec.status = rec.state
            elif rec.date_to < today:
                rec.status = 'expired'
            elif rec.date_from > today:
                rec.status = 'upcoming'
            else:
                rec.status = 'active'

    @api.model
    def _ff_live(self, employee):
        """Approved requests covering today."""
        today = fields.Date.context_today(self)
        return self.sudo().search([('employee_id', '=', employee.id), ('state', '=', 'approved'),
                                   ('date_from', '<=', today), ('date_to', '>=', today)])

    def ff_decide(self, approver, approve, note=None):
        is_admin = self.env.user.has_group('ff_base.group_ff_admin')
        for rec in self:
            if rec.state != 'pending':
                raise ValidationError(self.env._('This request is already decided.'))
            if not (approver and approver._ff_is_manager_of(rec.employee_id)) and not is_admin:
                raise ValidationError(self.env._("Only the person's manager can decide this."))
            rec.sudo().write({'state': 'approved' if approve else 'rejected',
                              'decided_by_id': approver.id or False,
                              'decided_at': fields.Datetime.now(), 'decision_note': note or False})
        return self

    def action_approve(self):
        return self.ff_decide(self.env.user.employee_id, True)

    def action_reject(self):
        return self.ff_decide(self.env.user.employee_id, False)
