from odoo import fields, models


class HrEmployee(models.Model):
    _inherit = 'hr.employee'

    ff_allowance_policy_id = fields.Many2one(
        'ff.allowance.policy', string='Allowance Policy',
        help='Leave empty to use the policy of the employee\'s department (or the company default).')

    def _ff_day_vehicle(self, day):
        """(vehicle type, whose scooter) chosen at the first check-in of ``day``; False where not asked."""
        self.ensure_one()
        start, end = self._ff_day_bounds(day)
        first = self.env['hr.attendance'].sudo().search([
            ('employee_id', '=', self.id), ('check_in', '>=', start), ('check_in', '<', end)],
            order='check_in', limit=1)
        if not first:
            return False, False
        owner = first.ff_vehicle_owner if 'ff_vehicle_owner' in first._fields else False
        return first.ff_vehicle_type or False, owner or False
