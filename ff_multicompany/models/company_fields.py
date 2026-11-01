from odoo import fields, models


class FfVisit(models.Model):
    _inherit = 'ff.visit'

    company_id = fields.Many2one(related='employee_id.company_id', store=True, index=True)


class FfBeatPlan(models.Model):
    _inherit = 'ff.beat.plan'

    company_id = fields.Many2one(related='employee_id.company_id', store=True, index=True)
