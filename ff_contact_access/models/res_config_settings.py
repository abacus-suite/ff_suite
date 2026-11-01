from odoo import fields, models


class ResConfigSettings(models.TransientModel):
    _inherit = 'res.config.settings'

    ff_contact_visibility = fields.Selection(
        [('territory', 'Territory wise'), ('beat', 'Beat wise'), ('city', 'City wise'), ('open', 'Open access')],
        string='Contacts Shown By', config_parameter='ff_base.contact_visibility', default='territory',
        help='Which contacts an employee sees in the app.\n'
             'Territory wise: the contacts of their primary and secondary territories.\n'
             'Beat wise: the contacts on their assigned beats.\n'
             'City wise: the contacts of their cities.\n'
             'Open access: every contact of the company.\n'
             'A person with nothing set for the chosen kind sees every contact, and contacts they or their team '
             'added, or are assigned to, are always theirs.')
