from odoo import api, models
from odoo.fields import Domain


class ResPartner(models.Model):
    _inherit = 'res.partner'

    @api.model
    def _ff_access_rule(self, employee):
        return self.env['ff.contact.access.rule']._ff_pick(employee.sudo())

    @api.model
    def _ff_visible_domain(self, employee):
        rule = self._ff_access_rule(employee)
        if not rule:
            return super()._ff_visible_domain(employee)
        employee = employee.sudo()
        base = None
        if rule.mode in ('open', 'assigned'):
            forced = self.with_context(ff_force_access='open' if rule.mode == 'open' else 'scoped')
            base = super(ResPartner, forced)._ff_visible_domain(employee)
        grants = self.env['ff.contact.access.request']._ff_live(employee)

        beats = employee.ff_route_ids if rule.mode == 'beat' else self.env['ff.beat']
        beats |= grants.filtered(lambda g: g.scope_type == 'beat').beat_id
        territories = employee.ff_territory_ids if rule.mode == 'territory' else self.env['ff.territory']
        territories |= grants.filtered(lambda g: g.scope_type == 'territory').territory_id
        cities = employee.ff_district_ids if rule.mode == 'city' else self.env['ff.district']
        cities |= grants.filtered(lambda g: g.scope_type == 'city').district_id

        if base is not None and not (beats or territories or cities):
            return base
        where = []
        if beats:
            where.append([('ff_beat_line_ids.beat_id', 'in', beats.ids)])
        if territories:
            where.append([('ff_beat_line_ids.beat_id.territory_id', 'in', territories.ids)])
        if cities:
            where.append([('ff_district_id', 'in', cities.ids)])
            where.append([('ff_beat_line_ids.beat_id.district_id', 'in', cities.ids)])
        mine = (employee | employee._ff_subordinates()).ids
        # Their own people stay theirs whatever the rule says.
        where.append([('ff_employee_ids', 'in', mine)])
        where.append([('ff_created_by_employee_id', 'in', mine)])
        place = Domain.OR([Domain(w) for w in where])
        if base is not None:
            place = Domain.OR([place, Domain(base)])
        approval = ['|', '|', ('ff_approval_state', '=', 'approved'), ('ff_approval_state', '=', False),
                    '&', ('ff_approval_state', '=', 'pending'), ('ff_created_by_employee_id', '=', employee.id)]
        # A lead stays with whoever added it and the managers above them.
        lead = ['|', ('ff_category_type', '!=', 'lead'),
                '|', ('ff_created_by_employee_id', 'in', mine), ('ff_employee_ids', 'in', mine)]
        return list(Domain([('ff_is_client', '=', True)]) & place & Domain(lead) & Domain(approval))
