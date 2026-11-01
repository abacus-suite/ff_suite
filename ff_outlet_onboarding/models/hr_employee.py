from odoo import fields, models


class HrEmployee(models.Model):
    _inherit = 'hr.employee'

    ff_edit_after_onboard = fields.Boolean(
        string='Can Edit Onboarded Contacts',
        help='Once a contact is onboarded, nobody can edit it in the app. Tick this for the people who may.')
