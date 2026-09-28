from odoo import api, fields, models


class FfTeam(models.Model):
    _name = 'ff.team'
    _description = 'Field Team / Region'
    _inherit = ['mail.thread']
    _order = 'name'

    name = fields.Char(required=True, tracking=True)
    code = fields.Char()
    manager_id = fields.Many2one('hr.employee', string='Team Manager', tracking=True)
    parent_id = fields.Many2one('ff.team', string='Parent Team', index=True)
    child_ids = fields.One2many('ff.team', 'parent_id', string='Sub Teams')
    member_ids = fields.One2many('hr.employee', 'ff_team_id', string='Members')
    member_count = fields.Integer(compute='_compute_member_count')
    company_id = fields.Many2one('res.company', required=True, default=lambda self: self.env.company)
    active = fields.Boolean(default=True)

    _name_company_uniq = models.Constraint(
        'UNIQUE(name, company_id)',
        'A team with this name already exists.',
    )

    @api.depends('member_ids')
    def _compute_member_count(self):
        for team in self:
            team.member_count = len(team.member_ids)
