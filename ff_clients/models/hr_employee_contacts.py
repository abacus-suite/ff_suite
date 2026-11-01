"""A way to see exactly what one person's app will show.

"The app shows 17 but the database has 30" is a question about a domain, and
the quickest honest answer is to open that very domain in Odoo. The button on
the employee form does that: the same rule the app uses, nothing else.
"""
from odoo import models


class HrEmployeeAppContacts(models.Model):
    _inherit = 'hr.employee'

    def action_ff_app_contacts(self):
        """Open the contacts this employee sees in the app, by the app's own rule."""
        self.ensure_one()
        domain = self.env['res.partner']._ff_visible_domain(self)
        access = self.env['res.partner']._ff_contact_access()
        return {
            'type': 'ir.actions.act_window',
            'name': self.env._('%(name)s sees these in the app (%(mode)s)',
                               name=self.name,
                               mode=self.env._('shared') if access == 'open' else self.env._('own and team')),
            'res_model': 'res.partner',
            'view_mode': 'list,form',
            'domain': domain,
            'context': {
                'search_default_group_category': 1,
                'create': False,
            },
            'help': '''<p class="o_view_nocontent_smiling_face">Nothing matches the rule</p>
                <p>These are the contacts the app would list for this person, worked out the same way
                the app does. A contact missing here is missing there: check its approval state,
                its contact type, and whether anybody is assigned to it.</p>''',
        }
