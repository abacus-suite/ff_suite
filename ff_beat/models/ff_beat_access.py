"""Which beats a person may plan and put customers on.

The contact list has its own access rules (see ff_contact_access); the beats a person can choose from
have to follow the very same rules, or a person limited to one beat would still be offered all of them
when they check in. This is the one question every beat list asks, so there is one answer.
"""
from odoo import api, models


class FfBeatAccess(models.Model):
    _inherit = 'ff.beat'

    @api.model
    def _ff_beat_usable(self, beats, employee):
        """Approved beats, and the pending ones this employee drew themselves; turned-down ones for nobody."""
        return beats.filtered(lambda b: b.active and (b.ff_approval_state == 'approved' or (
            b.ff_approval_state == 'pending' and b.ff_created_by_employee_id == employee)))

    @api.model
    def ff_beats_for(self, employee, date=None):
        """The beats this employee may choose from (on ``date``, when it matters).

        With shared contacts everybody plans from every beat. Otherwise it is their own, and only when
        they have none is the whole company's list offered, as before.
        """
        employee = employee.sudo()
        Beat = self.sudo()
        everything = Beat.search([('company_id', 'in', (False, employee.company_id.id))])
        shared = self.env['res.partner']._ff_contact_access() == 'open'
        own = self._ff_beat_usable(employee.ff_route_ids, employee)
        if shared or not own:
            return self._ff_beat_usable(everything, employee)
        return own | self._ff_beat_usable(everything.filtered(lambda b: b.ff_created_by_employee_id == employee), employee)

    @api.model
    def ff_can_use_beat(self, employee, beat, date=None):
        return beat.sudo() in self.ff_beats_for(employee, date)
