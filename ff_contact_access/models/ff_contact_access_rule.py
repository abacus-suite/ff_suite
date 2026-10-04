from odoo import fields, models

MODES = [
    ('open', 'Open - every contact'),
    ('territory', 'Territory wise'),
    ('city', 'City wise'),
    ('beat', 'Allowed beats only'),
    ('assigned', 'Assigned to them (own and team)'),
]


class FfContactAccessRule(models.Model):
    """How a person's contact list is worked out.

    A rule naming employees applies to them. A rule naming nobody is a default
    for everyone without a rule of their own. With no rule at all the old
    setting (Settings > Who Sees Which Contacts) still decides.
    """
    _name = 'ff.contact.access.rule'
    _description = 'Contact Access Rule'
    _order = 'sequence, id'

    name = fields.Char(required=True)
    sequence = fields.Integer(default=10)
    active = fields.Boolean(default=True)
    mode = fields.Selection(MODES, required=True, default='beat')
    employee_ids = fields.Many2many('hr.employee', string='Employees',
                                    help='Leave empty to make this the default for everyone without a rule of their own.')
    note = fields.Char()

    def _ff_pick(self, employee):
        """Employee-specific rule first, else the first default."""
        rules = self.sudo().search([])
        own = rules.filtered(lambda r: employee in r.employee_ids)[:1]
        return own or rules.filtered(lambda r: not r.employee_ids)[:1]
