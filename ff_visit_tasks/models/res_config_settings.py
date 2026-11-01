from odoo import fields, models


class ResConfigSettings(models.TransientModel):
    _inherit = 'res.config.settings'

    ff_note_approval = fields.Selection([
        ('manual', 'A manager approves each one'),
        ('auto', 'Approved automatically'),
    ], string='Credit / Debit Notes', config_parameter='ff_base.note_approval', default='manual',
        help='Debit notes for samples and free goods, and credit notes for damaged stock, are raised '
             'from the field. Choose whether a manager must approve each one or they stand as soon as they are raised.')
