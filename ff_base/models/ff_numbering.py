"""Reference numbers, in the format the office asks for.

A claim only becomes a document worth filing once somebody approves it, so the
number is handed out then rather than at creation - no gaps for claims that were
never approved. The format itself lives on an ``ir.sequence``, which already
knows about prefixes, padding and the %(year)s style placeholders, and Settings
edits that sequence rather than inventing a second way of describing a number.
"""
from odoo import api, fields, models


class FfNumberedMixin(models.AbstractModel):
    _name = 'ff.numbered.mixin'
    _description = 'Numbered on Approval'

    # Each model says which sequence it draws from.
    _ff_sequence_code = None

    ff_reference = fields.Char(string='Reference', copy=False, readonly=True, index=True,
                               help='Given when the document is approved, in the format set in Settings.')

    def _ff_assign_reference(self):
        """Number the records that have just been approved and have none yet."""
        for record in self.sudo():
            if record.ff_reference or not record._ff_sequence_code:
                continue
            number = record.env['ir.sequence'].next_by_code(record._ff_sequence_code)
            if number:
                record.ff_reference = number

    @api.model
    def _ff_sequence(self, code):
        return self.env['ir.sequence'].sudo().search([('code', '=', code)], limit=1)


class FfNumberSettings(models.TransientModel):
    """Settings read and write the sequences directly, so what you type is what
    the next document gets."""
    _inherit = 'res.config.settings'

    ff_expense_prefix = fields.Char(string='Expense Number Format')
    ff_expense_padding = fields.Integer(string='Expense Number Digits')
    ff_allowance_prefix = fields.Char(string='Allowance Number Format')
    ff_allowance_padding = fields.Integer(string='Allowance Number Digits')

    # code on the sequence -> (prefix field, padding field)
    FF_NUMBER_FIELDS = {
        'ff.expense.claim': ('ff_expense_prefix', 'ff_expense_padding'),
        'ff.allowance.claim': ('ff_allowance_prefix', 'ff_allowance_padding'),
    }

    @api.model
    def get_values(self):
        values = super().get_values()
        Sequence = self.env['ir.sequence'].sudo()
        for code, (prefix_field, padding_field) in self.FF_NUMBER_FIELDS.items():
            sequence = Sequence.search([('code', '=', code)], limit=1)
            values[prefix_field] = sequence.prefix or ''
            values[padding_field] = sequence.padding or 0
        return values

    def set_values(self):
        super().set_values()
        Sequence = self.env['ir.sequence'].sudo()
        for code, (prefix_field, padding_field) in self.FF_NUMBER_FIELDS.items():
            sequence = Sequence.search([('code', '=', code)], limit=1)
            if not sequence:
                continue
            sequence.write({
                'prefix': self[prefix_field] or '',
                'padding': max(self[padding_field] or 1, 1),
            })
