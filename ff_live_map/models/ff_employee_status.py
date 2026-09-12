"""Data behind the live map: where everybody is, right now."""
from odoo import api, models

from odoo.addons.ff_base.tools import google_maps_key, to_iso


class FfEmployeeStatus(models.Model):
    _inherit = 'ff.employee.status'

    @api.model
    def ff_live_map(self):
        """Positions of everybody inside the caller's data access scope.

        Read as the current user, so the record rules decide who is on the map.
        """
        employees = self.env.user.ff_scope_employee_ids()
        statuses = self.search([('employee_id', 'in', employees)])
        visits = {
            visit.employee_id.id: visit
            for visit in self.env['ff.visit'].search(
                [('employee_id', 'in', statuses.employee_id.ids), ('state', '=', 'ongoing')])
        }
        people = []
        for status in statuses:
            employee = status.employee_id
            visit = visits.get(employee.id)
            located = bool(status.last_ping_at and (status.latitude or status.longitude))
            people.append({
                'id': employee.id,
                'name': employee.name,
                'code': employee.ff_employee_code or '',
                'team': employee.ff_team_id.name or '',
                'job': employee.job_title or '',
                'phone': employee.mobile_phone or employee.work_phone or '',
                'avatar': '/web/image/hr.employee/%s/avatar_128' % employee.id,
                'lat': status.latitude if located else False,
                'lng': status.longitude if located else False,
                'accuracy': round(status.accuracy or 0.0),
                'punched_in': status.punched_in,
                'punched_in_at': to_iso(status.punched_in_at),
                'last_ping_at': to_iso(status.last_ping_at),
                'battery': status.battery,
                'is_charging': status.is_charging,
                'gps_on': status.gps_on,
                'is_inactive': status.is_inactive,
                'is_signal_lost': status.is_signal_lost,
                'is_low_battery': status.is_low_battery,
                'at_client': visit.partner_id.display_name if visit else '',
                'at_client_id': visit.partner_id.id if visit else False,
                'state': self._ff_map_state(status, visit),
            })
        people.sort(key=lambda row: (not row['punched_in'], row['name'] or ''))
        return {
            'google_maps_key': google_maps_key(self.env),
            'people': people,
        }

    @api.model
    def _ff_map_state(self, status, visit):
        """One word for the colour of the pin."""
        if not status.punched_in:
            return 'off'
        if status.is_signal_lost or not status.gps_on:
            return 'no_signal'
        if status.is_inactive:
            return 'inactive'
        if visit:
            return 'at_client'
        return 'moving'
