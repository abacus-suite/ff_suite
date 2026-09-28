from odoo import models, fields


class L4eSalaryRevision(models.Model):
    _name = 'l4e.salary.revision'
    _description = 'Salary Revision History'
    _order = 'effective_date asc'

    employee_id = fields.Many2one(
        'hr.employee',
        string='Employee',
        required=True,
        ondelete='cascade',
    )
    amount = fields.Float(
        string='Salary Amount (Rs.)',
        required=True,
    )
    effective_date = fields.Date(
        string='Effective Date',
        required=True,
    )
    note = fields.Char(
        string='Note',
        help='e.g. W.E.F 01.11.2024',
    )
