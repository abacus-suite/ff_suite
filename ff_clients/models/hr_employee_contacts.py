"""A way to see exactly what one person's app will show.

"The app shows 17 but the database has 30" is a question about a domain, and
the quickest honest answer is to open that very domain in Odoo. The button on
the employee form does that: the same rule the app uses, nothing else.
"""
from odoo import fields, models
from odoo.fields import Domain


class HrEmployeeAppContacts(models.Model):
    _inherit = 'hr.employee'

    ff_lead_edit = fields.Boolean(
        string='Lead Edit', tracking=True,
        help='On: this person sees the Edit button on a lead in the app and can change its details. '
             'Off: leads are view only for them.')
    ff_allocated_outlets = fields.Boolean(
        string='Allocated Outlets', tracking=True,
        help='On: this person sees, in the app, only the outlets that have their name on them (Field Employees '
             'on the contact). Off: the usual rule decides (shared, or by territory, beat or city).')
    ff_allocated_distributors = fields.Boolean(
        string='Allocated Distributors', tracking=True,
        help='On: this person sees, in the app, only the distributors that have their name on them (Field Employees '
             'on the contact). Off: the usual rule decides (shared, or by territory, beat or city).')

    ff_outlet_count = fields.Integer(compute='_compute_ff_contact_counts', string='Outlets')
    ff_distributor_count = fields.Integer(compute='_compute_ff_contact_counts', string='Distributors')
    ff_lead_count = fields.Integer(compute='_compute_ff_contact_counts', string='Leads')

    def _ff_category_domains(self):
        Partner = self.env['res.partner']
        distributor = [('ff_category_type', '=', 'distributor')]
        if 'ff_is_distributor' in Partner._fields:
            distributor = ['|'] + distributor + [('ff_is_distributor', '=', True)]
        if 'is_distributor' in Partner._fields:
            distributor = ['|'] + distributor + [('is_distributor', '=', True)]

        outlet = ['|', ('ff_category_type', '=', False), ('ff_category_type', 'not in', ('distributor', 'lead'))]
        if 'ff_is_distributor' in Partner._fields:
            outlet.append(('ff_is_distributor', '!=', True))
        if 'is_distributor' in Partner._fields:
            outlet.append(('is_distributor', '!=', True))

        lead = [('ff_category_type', '=', 'lead')]
        if 'client_status' in Partner._fields:
            lead = ['|'] + lead + [('client_status', '=', 'new_lead')]

        return outlet, distributor, lead

    def _ff_base_place_domain(self):
        self.ensure_one()
        Partner = self.env['res.partner']
        if hasattr(Partner, '_ff_visible_domain_by_rule'):
            return Partner._ff_visible_domain_by_rule(self)
        if hasattr(Partner, '_ff_visible_domain'):
            return Partner._ff_visible_domain(self)
        return [('ff_is_client', '=', True)]

    def _get_ff_outlets_domain(self):
        self.ensure_one()
        outlet_filter, _, _ = self._ff_category_domains()
        if self.ff_allocated_outlets:
            return list(Domain(outlet_filter) & Domain([('ff_employee_ids', 'in', [self.id])]))
        else:
            base_rule_dom = self._ff_base_place_domain()
            return list(Domain(outlet_filter) & Domain(base_rule_dom))

    def _get_ff_distributors_domain(self):
        self.ensure_one()
        _, dist_filter, _ = self._ff_category_domains()
        if self.ff_allocated_distributors:
            return list(Domain(dist_filter) & Domain([('ff_employee_ids', 'in', [self.id])]))
        else:
            base_rule_dom = self._ff_base_place_domain()
            return list(Domain(dist_filter) & Domain(base_rule_dom))

    def _get_ff_leads_domain(self):
        self.ensure_one()
        _, _, lead_filter = self._ff_category_domains()
        base_rule_dom = self._ff_base_place_domain()
        return list(Domain(lead_filter) & Domain(base_rule_dom))

    def _compute_ff_contact_counts(self):
        Partner = self.env['res.partner']
        for emp in self:
            emp.ff_outlet_count = Partner.search_count(emp._get_ff_outlets_domain())
            emp.ff_distributor_count = Partner.search_count(emp._get_ff_distributors_domain())
            emp.ff_lead_count = Partner.search_count(emp._get_ff_leads_domain())

    def action_view_ff_outlets(self):
        self.ensure_one()
        return {
            'type': 'ir.actions.act_window',
            'name': self.env._('%(name)s - Outlets', name=self.name),
            'res_model': 'res.partner',
            'view_mode': 'list,form',
            'domain': self._get_ff_outlets_domain(),
            'context': {'default_ff_is_client': True},
        }

    def action_view_ff_distributors(self):
        self.ensure_one()
        return {
            'type': 'ir.actions.act_window',
            'name': self.env._('%(name)s - Distributors', name=self.name),
            'res_model': 'res.partner',
            'view_mode': 'list,form',
            'domain': self._get_ff_distributors_domain(),
            'context': {'default_ff_is_client': True, 'default_ff_is_distributor': True},
        }

    def action_view_ff_leads(self):
        self.ensure_one()
        return {
            'type': 'ir.actions.act_window',
            'name': self.env._('%(name)s - Leads', name=self.name),
            'res_model': 'res.partner',
            'view_mode': 'list,form',
            'domain': self._get_ff_leads_domain(),
            'context': {'default_ff_is_client': True},
        }

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
