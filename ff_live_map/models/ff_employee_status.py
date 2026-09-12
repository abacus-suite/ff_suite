"""Data behind the live map: where everybody is, right now."""
from odoo import api, models

from odoo.addons.ff_base.tools import google_maps_key, to_iso


class FfEmployeeStatus(models.Model):
    _inherit = 'ff.employee.status'

    @api.model
    def _ff_map_employees(self):
        """Everybody the current user may watch.

        Normally the user's own data access scope decides. An administrator is
        the exception: watching the whole field is the point of the screen, and
        their own employee record (if any) would otherwise narrow it to one card.
        """
        Employee = self.env['hr.employee'].sudo()
        company_domain = [('company_id', 'in', self.env.companies.ids)]
        if self.env.user.has_group('ff_base.group_ff_admin'):
            return Employee.search(company_domain)
        scope_ids = self.env.user.ff_scope_employee_ids()
        if scope_ids:
            return Employee.browse(scope_ids).exists()
        if self.env.user.has_group('ff_base.group_ff_manager'):
            return Employee.search(company_domain)
        return Employee.browse()

    @api.model
    def ff_live_map(self, with_clients=False):
        """Positions of everybody the user may watch, plus optional customer pins."""
        employees = self._ff_map_employees()
        statuses = {
            status.employee_id.id: status
            for status in self.sudo().search([('employee_id', 'in', employees.ids)])
        }
        visits = {
            visit.employee_id.id: visit
            for visit in self.env['ff.visit'].sudo().search(
                [('employee_id', 'in', employees.ids), ('state', '=', 'ongoing')])
        }
        people = [self._ff_map_person(employee, statuses.get(employee.id), visits.get(employee.id))
                  for employee in employees]
        people.sort(key=lambda row: (not row['punched_in'], row['name'] or ''))
        data = {
            'google_maps_key': google_maps_key(self.env),
            'people': people,
            'clients': self._ff_map_clients(employees) if with_clients else [],
        }
        return data

    @api.model
    def _ff_map_person(self, employee, status, visit):
        located = bool(status and status.last_ping_at and (status.latitude or status.longitude))
        return {
            'id': employee.id,
            'name': employee.name,
            'code': employee.ff_employee_code or '',
            'team': employee.ff_team_id.name or '',
            'job': employee.job_title or '',
            'phone': employee.mobile_phone or employee.work_phone or '',
            'avatar': '/web/image/hr.employee/%s/avatar_128' % employee.id,
            'lat': status.latitude if located else False,
            'lng': status.longitude if located else False,
            'accuracy': round(status.accuracy or 0.0) if status else 0,
            'punched_in': bool(status and status.punched_in),
            'punched_in_at': to_iso(status.punched_in_at) if status else False,
            'last_ping_at': to_iso(status.last_ping_at) if status else False,
            'battery': status.battery if status else 0,
            'is_charging': bool(status and status.is_charging),
            'gps_on': bool(status and status.gps_on),
            'is_inactive': bool(status and status.is_inactive),
            'is_signal_lost': bool(status and status.is_signal_lost),
            'is_low_battery': bool(status and status.is_low_battery),
            'at_client': visit.partner_id.display_name if visit else '',
            'at_client_id': visit.partner_id.id if visit else False,
            'visit_since': to_iso(visit.check_in_at) if visit else False,
            'state': self._ff_map_state(status, visit),
        }

    @api.model
    def _ff_map_clients(self, employees):
        """Customers of these employees that have a location, to show alongside."""
        partners = self.env['res.partner'].sudo().search([
            ('ff_is_client', '=', True),
            ('ff_employee_ids', 'in', employees.ids),
            '|', ('partner_latitude', '!=', 0), ('partner_longitude', '!=', 0),
        ], limit=500)
        return [{
            'id': partner.id,
            'name': partner.display_name,
            'lat': partner.partner_latitude,
            'lng': partner.partner_longitude,
            'category': partner.ff_category_id.name or '',
        } for partner in partners]

    @api.model
    def _ff_map_state(self, status, visit):
        """One word for the colour of the pin."""
        if not status or not status.punched_in:
            return 'off'
        if status.is_signal_lost or not status.gps_on:
            return 'no_signal'
        if status.is_inactive:
            return 'inactive'
        if visit:
            return 'at_client'
        return 'moving'
