"""The beats follow the contact access rule.

A person ruled to one beat is offered that beat, not every beat in the company. Territory and city rules
offer the beats inside them, an approved access request adds what it names for its dates, and the
beats somebody is assigned or drew themselves always stay theirs.
"""
from odoo import api, models


class FfBeatAccess(models.Model):
    _inherit = 'ff.beat'

    @api.model
    def ff_beats_for(self, employee, date=None):
        rule = self.env['res.partner']._ff_access_rule(employee)
        if not rule:
            return super().ff_beats_for(employee, date)
        employee = employee.sudo()
        if rule.mode == 'open':
            return super(FfBeatAccess, self.with_context(ff_force_access='open')).ff_beats_for(employee, date)

        Beat = self.sudo()
        everything = Beat.search([('company_id', 'in', (False, employee.company_id.id))])
        grants = self.env['ff.contact.access.request']._ff_live(employee, date)

        # Assigned to them, and what they drew themselves, are theirs under every rule.
        beats = employee.ff_route_ids | everything.filtered(lambda b: b.ff_created_by_employee_id == employee)
        if rule.mode == 'assigned':
            beats |= employee._ff_subordinates().sudo().ff_route_ids
        if rule.mode == 'territory':
            beats |= everything.filtered(lambda b: b.territory_id in employee.ff_territory_ids)
        if rule.mode == 'city':
            cities = employee.ff_district_ids
            beats |= everything.filtered(
                lambda b: b.district_id in cities or b.territory_id.district_id in cities)

        # A dated access request adds its territory, beat or city while it lasts.
        beats |= grants.filtered(lambda g: g.scope_type == 'beat').beat_id
        territories = grants.filtered(lambda g: g.scope_type == 'territory').territory_id
        cities = grants.filtered(lambda g: g.scope_type == 'city').district_id
        if territories:
            beats |= everything.filtered(lambda b: b.territory_id in territories)
        if cities:
            beats |= everything.filtered(lambda b: b.district_id in cities or b.territory_id.district_id in cities)
        return self._ff_beat_usable(beats, employee)
