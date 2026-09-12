from odoo import api, fields, models

MODE_TYPES = [
    ('cash', 'Cash'),
    ('online', 'Online / UPI / bank transfer'),
    ('cheque', 'Cheque'),
    ('pdc', 'Post-dated cheque (PDC)'),
]


class FfCollectionMode(models.Model):
    """How money may be collected. Only enabled modes appear in Odoo and the app."""
    _name = 'ff.collection.mode'
    _description = 'Collection Mode'
    _order = 'sequence, id'

    name = fields.Char(required=True, translate=True)
    mode_type = fields.Selection(MODE_TYPES, string='Type', required=True, default='cash')
    sequence = fields.Integer(default=10)
    department_ids = fields.Many2many('hr.department', string='Departments', help='Leave empty for every department.')
    requires_reference = fields.Boolean(string='Reference Required',
                                        help='Cheque number, UTR or transaction reference.')
    requires_photo = fields.Boolean(string='Photo Required', help='Photo of the cheque or the receipt.')
    requires_instrument_date = fields.Boolean(string='Cheque Date Required')
    needs_deposit = fields.Boolean(string='Must Be Deposited', default=True,
                                   help='The money or instrument has to be handed over to the office.')
    max_amount = fields.Monetary(string='Maximum per Collection', help='0 = no limit.')
    company_id = fields.Many2one('res.company', required=True, default=lambda self: self.env.company)
    currency_id = fields.Many2one(related='company_id.currency_id')
    active = fields.Boolean(default=True)

    _name_company_uniq = models.Constraint('UNIQUE(name, company_id)', 'This collection mode already exists.')

    @api.model
    def ff_for_employee(self, employee):
        employee = employee.sudo()
        return self.sudo().search([
            ('company_id', 'in', employee.company_id.ids),
            '|', ('department_ids', '=', False), ('department_ids', 'in', employee.department_id.ids),
        ])
