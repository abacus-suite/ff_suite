from odoo import api, fields, models


class FfAttributionMixin(models.AbstractModel):
    """Adds "who in the field earned this" to a business document.

    Every model that inherits it gets the employee, and - derived from the
    employee - the team and department, so reports can be grouped either way.
    The route and the city come from the contact, because that is where the
    geography of a sale really lives.
    """
    _name = 'ff.attribution.mixin'
    _description = 'Field Force Attribution'

    ff_employee_id = fields.Many2one('hr.employee', string='Field Employee', index=True,
                                     tracking=True, default=lambda self: self._ff_default_employee(),
                                     help='Field employee credited for this document.')
    ff_team_id = fields.Many2one(related='ff_employee_id.ff_team_id', store=True, string='Field Team')
    ff_department_id = fields.Many2one(related='ff_employee_id.department_id', store=True, string='Field Department')
    ff_route_id = fields.Many2one('ff.beat', string='Route', index=True,
                                  help='Route the contact belongs to, at the time of this document.')
    ff_district_id = fields.Many2one('ff.district', string='City / District', index=True)

    @api.model
    def _ff_default_employee(self):
        return self.env.user.employee_id

    def _ff_partner_for_attribution(self):
        """The contact whose route and city should be used. Override where the
        customer sits on another field."""
        self.ensure_one()
        return self.partner_id if 'partner_id' in self._fields else self.env['res.partner']

    def _ff_attribution_from_partner(self, partner=None, force=False):
        """Fill in employee, route and city from the contact. Never overwrites a
        value somebody chose, unless ``force``."""
        for record in self:
            contact = (partner or record._ff_partner_for_attribution()).sudo()
            if not contact:
                continue
            if force or not record.ff_employee_id:
                employees = contact.ff_employee_ids
                record.ff_employee_id = employees[:1].id if employees else record.ff_employee_id.id
            if force or not record.ff_route_id:
                routes = contact.ff_route_ids
                record.ff_route_id = routes[:1].id if routes else record.ff_route_id.id
            if force or not record.ff_district_id:
                record.ff_district_id = contact.ff_district_id.id or record.ff_district_id.id

    def _ff_attribution_values(self):
        """The stamp of this document, ready to copy onto a document it creates."""
        self.ensure_one()
        return {
            'ff_employee_id': self.ff_employee_id.id,
            'ff_route_id': self.ff_route_id.id,
            'ff_district_id': self.ff_district_id.id,
        }
