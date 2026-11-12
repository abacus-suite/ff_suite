from odoo import api, fields, models
from odoo.fields import Domain


class ResPartner(models.Model):
    _inherit = 'res.partner'

    ff_territory_id = fields.Many2one(
        'ff.territory', string='City / Town', compute='_compute_ff_territory_id', store=True, readonly=False,
        index=True, domain="[('district_id', '=?', ff_district_id)]",
        help='Taken from the territory of the beat of the contact. It can also be set here, for a contact that '
             'is not on a beat yet.')
    ff_area_id = fields.Many2one(
        'ff.area', string='Area', index=True, domain="[('territory_id', '=?', ff_territory_id)]",
        help='The neighbourhood of the contact inside its territory. The app filters the client list by it.')
    ff_secondary_territory_ids = fields.Many2many(
        'ff.territory', 'ff_partner_secondary_territory_rel', 'partner_id', 'territory_id',
        string='Secondary Cities / Towns',
        help='Additional territories covered by this distributor.')
    ff_territory_ids = fields.Many2many(
        'ff.territory', compute='_compute_ff_territory_ids', string='All Cities / Towns')

    @api.depends('ff_beat_line_ids.beat_id.territory_id')
    def _compute_ff_territory_id(self):
        for partner in self:
            territories = partner.ff_beat_line_ids.beat_id.territory_id
            if territories:
                partner.ff_territory_id = territories[:1]

    @api.depends('ff_territory_id', 'ff_secondary_territory_ids')
    def _compute_ff_territory_ids(self):
        for partner in self:
            partner.ff_territory_ids = partner.ff_territory_id | partner.ff_secondary_territory_ids

    @api.model
    def _ff_access_rule(self, employee):
        return self.env['ff.contact.access.rule']._ff_pick(employee.sudo())

    @api.model
    def _ff_visible_domain(self, employee):
        """By the access rule, then narrowed by the employee's "Allocated Outlets / Distributors" switches."""
        from odoo.fields import Domain
        domain = self._ff_visible_domain_by_rule(employee)
        allocation = self._ff_allocation_domain(employee)
        return list(Domain(domain) & Domain(allocation)) if allocation else domain

    @api.model
    def _ff_visible_domain_by_rule(self, employee):
        # A rule given to an employee comes first: it decides for that person, whatever the setting says.
        rule_first = self._ff_access_rule(employee)
        if rule_first and rule_first.mode == 'open':
            return super(ResPartner, self.with_context(ff_all_contacts=True))._ff_visible_domain(employee)
        if self._ff_see_all() and not rule_first:
            base = super()._ff_visible_domain(employee)
            mode = self.env['ir.config_parameter'].sudo().get_param('ff_base.contact_visibility') or 'territory'
            if mode == 'open':
                return base
            emp = employee.sudo()
            # Somebody in employee mode (a manager too) sees their own places, not their team's.
            team = emp if self.env.context.get('ff_only_me') else emp | emp._ff_subordinates()
            own = [('ff_created_by_employee_id', 'in', team.ids), ('ff_employee_ids', 'in', team.ids)]
            if mode == 'beat':
                beats = team.mapped('ff_route_ids')
                if not beats:
                    return base  # nothing is set for this person: they see the company's list
                places = [Domain([('ff_beat_line_ids.beat_id', 'in', beats.ids)])]
            elif mode == 'city':
                cities = team.mapped('ff_district_ids')
                if not cities:
                    return base
                city_conds = [
                    Domain([('ff_district_id', 'in', cities.ids)]),
                    Domain([('ff_beat_line_ids.beat_id.district_id', 'in', cities.ids)]),
                ]
                if 'ff_secondary_district_ids' in self._fields:
                    city_conds.append(Domain([('ff_secondary_district_ids', 'in', cities.ids)]))
                places = [Domain.OR(city_conds)]
            else:
                territories = team.mapped('ff_territory_ids')
                # Territory-wise: the primary and secondary territories only. Nobody with none set sees the whole
                # company; they see what they added or are assigned to (a contact rule or the employee's
                # allocation switches widen that on purpose).
                places = []
                if territories:
                    # Territory-wise means the territories alone: what they or their team added or are assigned
                    # to elsewhere does not widen the list (a contact rule or the allocation switches can).
                    own = []
                    # A contact's own territory, secondary territories, or the territory of a beat it is on.
                    terr_conds = [Domain([('ff_territory_id', 'in', territories.ids)])]
                    if 'ff_secondary_territory_ids' in self._fields:
                        terr_conds.append(Domain([('ff_secondary_territory_ids', 'in', territories.ids)]))
                    places = [Domain.OR(terr_conds)]
            # The chosen kind of place, and whatever they or their team added or are assigned to.
            conds = places + [Domain([leaf]) for leaf in own]
            visibility_dom = Domain.OR(conds)
            return list(Domain(base) & visibility_dom)
        rule = self._ff_access_rule(employee)
        employee = employee.sudo()
        grants = self.env['ff.contact.access.request']._ff_live(employee)
        if not rule and not grants:
            return super()._ff_visible_domain(employee)
        base = None
        if not rule:
            # No rule of its own: the usual list, widened by what was granted.
            base = super()._ff_visible_domain(employee)
        elif rule.mode in ('open', 'assigned'):
            forced = self.with_context(ff_force_access='open' if rule.mode == 'open' else 'scoped')
            base = super(ResPartner, forced)._ff_visible_domain(employee)
        mode = rule.mode if rule else None

        beats = employee.ff_route_ids if mode == 'beat' else self.env['ff.beat']
        beats |= grants.filtered(lambda g: g.scope_type == 'beat').beat_id
        territories = employee.ff_territory_ids if mode == 'territory' else self.env['ff.territory']
        territories |= grants.filtered(lambda g: g.scope_type == 'territory').territory_id
        cities = employee.ff_district_ids if mode == 'city' else self.env['ff.district']
        cities |= grants.filtered(lambda g: g.scope_type == 'city').district_id

        if base is not None and not (beats or territories or cities):
            return base
        where = []
        if beats:
            where.append(Domain([('ff_beat_line_ids.beat_id', 'in', beats.ids)]))
        if territories:
            t_conds = [Domain([('ff_territory_id', 'in', territories.ids)]),
                       Domain([('ff_beat_line_ids.beat_id.territory_id', 'in', territories.ids)])]
            if 'ff_secondary_territory_ids' in self._fields:
                t_conds.append(Domain([('ff_secondary_territory_ids', 'in', territories.ids)]))
            where.append(Domain.OR(t_conds))
        if cities:
            c_conds = [Domain([('ff_district_id', 'in', cities.ids)]),
                       Domain([('ff_beat_line_ids.beat_id.district_id', 'in', cities.ids)])]
            if 'ff_secondary_district_ids' in self._fields:
                c_conds.append(Domain([('ff_secondary_district_ids', 'in', cities.ids)]))
            where.append(Domain.OR(c_conds))
        mine = (employee | employee._ff_subordinates()).ids
        # Their own people stay theirs whatever the rule says.
        where.append(Domain([('ff_employee_ids', 'in', mine)]))
        where.append(Domain([('ff_created_by_employee_id', 'in', mine)]))
        place = Domain.OR(where)
        if base is not None:
            place = Domain.OR([place, Domain(base)])
        approval = ['|', '|', ('ff_approval_state', '=', 'approved'), ('ff_approval_state', '=', False),
                    '&', ('ff_approval_state', '=', 'pending'), ('ff_created_by_employee_id', '=', employee.id)]
        # A lead stays with whoever added it and the managers above them.
        lead = ['|', ('ff_category_type', '!=', 'lead'),
                '|', ('ff_created_by_employee_id', 'in', mine), ('ff_employee_ids', 'in', mine)]
        shown = ['|', ('ff_category_id', '=', False), ('ff_category_id.show_in_app', '=', True)]
        return list(Domain([('ff_is_client', '=', True)]) & place & Domain(lead) & Domain(approval) & Domain(shown))

    @api.model
    def _ff_grant_partner_ids(self, employees):
        """Contacts these people were given access to (a beat, a territory or a city), for the days it is live."""
        Request = self.env['ff.contact.access.request']
        ids = set()
        for person in employees.sudo():
            for grant in Request._ff_live(person):
                if grant.scope_type == 'beat' and grant.beat_id:
                    domain = [('ff_beat_line_ids.beat_id', '=', grant.beat_id.id)]
                elif grant.scope_type == 'territory' and grant.territory_id:
                    domain = ['|', '|', ('ff_territory_id', '=', grant.territory_id.id),
                                        ('ff_secondary_territory_ids', 'in', [grant.territory_id.id]),
                                        ('ff_beat_line_ids.beat_id.territory_id', '=', grant.territory_id.id)]
                elif grant.scope_type == 'city' and grant.district_id:
                    domain = ['|', '|', ('ff_district_id', '=', grant.district_id.id),
                                        ('ff_secondary_district_ids', 'in', [grant.district_id.id]),
                                        ('ff_beat_line_ids.beat_id.district_id', '=', grant.district_id.id)]
                else:
                    continue
                ids.update(self.sudo().search([('ff_is_client', '=', True)] + domain).ids)
        return list(ids)
