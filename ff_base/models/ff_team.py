from odoo import api, fields, models


class FfTeam(models.Model):
    _name = 'ff.team'
    _description = 'Region'
    _inherit = ['mail.thread']
    _order = 'name'

    name = fields.Char(required=True, tracking=True)
    code = fields.Char()
    manager_id = fields.Many2one('hr.employee', string='Region Manager', tracking=True)
    parent_id = fields.Many2one('ff.team', string='Parent Region', index=True)
    child_ids = fields.One2many('ff.team', 'parent_id', string='Sub Regions')
    member_ids = fields.One2many('hr.employee', 'ff_team_id', string='Members')
    member_count = fields.Integer(compute='_compute_member_count')
    company_id = fields.Many2one('res.company', required=True, default=lambda self: self.env.company)
    active = fields.Boolean(default=True)

    _name_company_uniq = models.Constraint(
        'UNIQUE(name, company_id)',
        'A region with this name already exists.',
    )

    @api.depends('member_ids')
    def _compute_member_count(self):
        Employee = self.env['hr.employee'].sudo()
        for team in self:
            team.member_count = Employee.search_count(['|', ('ff_team_id', '=', team.id), ('ff_team_ids', 'in', team.ids)])
