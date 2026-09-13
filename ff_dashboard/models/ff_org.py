"""The organisation as a tree: who reports to whom, with their team and job.

Managers read the field through this shape - a person, their position, the team
they carry, and everybody underneath them.
"""
from odoo import api, models


class FfDashboardOrg(models.AbstractModel):
    _inherit = 'ff.dashboard'

    @api.model
    def ff_org_tree(self):
        """Everybody in view, nested under their reporting manager."""
        employees = self._ff_employees()
        if not employees:
            return {'roots': [], 'total': 0, 'unassigned': []}

        nodes = {employee.id: self._org_node(employee) for employee in employees}
        # This month's target achievement, when targets are in use.
        if 'ff.target' in self.env:
            first = self._ff_today().replace(day=1)
            for target in self.env['ff.target'].sudo().search([
                    ('scope', '=', 'employee'), ('employee_id', 'in', employees.ids), ('month', '=', first)]):
                node = nodes.get(target.employee_id.id)
                if node:
                    node['target'] = target.ff_row()['achievement']
        roots = []
        for employee in employees:
            node = nodes[employee.id]
            parent = nodes.get(employee.parent_id.id)
            if parent and parent is not node:
                parent['children'].append(node)
            else:
                roots.append(node)
        for node in nodes.values():
            node['children'].sort(key=lambda child: child['name'] or '')
            node['reports'] = self._count_reports(node)
        roots.sort(key=lambda node: (-node['reports'], node['name'] or ''))
        return {
            'roots': roots,
            'total': len(employees),
            'teams': len(employees.mapped('ff_team_id')),
            'managers': len([node for node in nodes.values() if node['children']]),
        }

    def _org_node(self, employee):
        status = self.env['ff.employee.status'].sudo().search(
            [('employee_id', '=', employee.id)], limit=1)
        return {
            'id': employee.id,
            'name': employee.name,
            'code': employee.ff_employee_code or '',
            'job': employee.job_title or employee.ff_designation_id.name or '',
            'team': employee.ff_team_id.name or '',
            'department': employee.department_id.name or '',
            'phone': employee.mobile_phone or employee.work_phone or '',
            'email': employee.work_email or '',
            'avatar': '/web/image/hr.employee/%s/avatar_128' % employee.id,
            'punched_in': bool(status and status.punched_in),
            'target': None,
            'children': [],
            'reports': 0,
        }

    def _count_reports(self, node):
        """Everybody under this person, however deep."""
        return sum(1 + self._count_reports(child) for child in node['children'])
