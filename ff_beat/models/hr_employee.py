from odoo import fields, models


class HrEmployee(models.Model):
    _inherit = 'hr.employee'

    ff_route_ids = fields.Many2many('ff.beat', 'ff_beat_employee_rel', 'employee_id', 'beat_id',
                                    string='Assigned Routes',
                                    help='Beats / patches this employee works. Plans can only use these routes.')
    ff_routes_per_day = fields.Selection(
        [('single', 'One route per day'), ('multiple', 'Several routes per day')],
        string='Routes per Day', default='single', required=True)

    def _ff_route_label(self):
        """Name this employee's department uses for routes, e.g. "Beat" or "Patch"."""
        self.ensure_one()
        route_type = self.env['ff.route.type'].ff_for_employee(self)[:1]
        return route_type.name or self.env._('Beat')
