from odoo import api, fields, models

FEATURES = ['attendance', 'tracking', 'routes', 'visits', 'orders', 'forms', 'allowance']


class FfAppProfile(models.Model):
    """What the mobile app shows, and the words it uses, per department."""
    _name = 'ff.app.profile'
    _description = 'Mobile App Profile'
    _order = 'sequence, id'

    name = fields.Char(required=True)
    sequence = fields.Integer(default=10)
    department_ids = fields.Many2many('hr.department', string='Departments',
                                      help='Departments using this profile. Leave empty for the default profile.')
    feature_attendance = fields.Boolean(string='Attendance', default=True)
    feature_tracking = fields.Boolean(string='Location Tracking', default=True)
    feature_routes = fields.Boolean(string='Routes (Beat / Patch)', default=True)
    feature_visits = fields.Boolean(string='Visits', default=True)
    feature_orders = fields.Boolean(string='Orders', default=True)
    feature_forms = fields.Boolean(string='Forms', default=True)
    feature_allowance = fields.Boolean(string='Travel Allowance', default=True)
    label_client = fields.Char(string='Word for "Client"', default='Client', translate=True,
                               help='e.g. Client, Outlet, Doctor, Dealer')
    label_visit = fields.Char(string='Word for "Visit"', default='Visit', translate=True, help='e.g. Visit, Call')
    label_order = fields.Char(string='Word for "Order"', default='Order', translate=True, help='e.g. Order, Booking')
    company_id = fields.Many2one('res.company', required=True, default=lambda self: self.env.company)
    active = fields.Boolean(default=True)

    @api.model
    def ff_for_employee(self, employee):
        employee = employee.sudo()
        profiles = self.sudo().search([('company_id', 'in', employee.company_id.ids)])
        specific = profiles.filtered(lambda p: employee.department_id and employee.department_id in p.department_ids)
        return (specific or profiles.filtered(lambda p: not p.department_ids))[:1]

    def ff_payload(self):
        """Feature flags and labels for the app; everything on when no profile exists."""
        profile = self[:1]
        return {
            'profile': profile.name or None,
            'features': {name: bool(profile['feature_%s' % name]) if profile else True for name in FEATURES},
            'labels': {
                'client': profile.label_client or 'Client',
                'visit': profile.label_visit or 'Visit',
                'order': profile.label_order or 'Order',
            },
        }
