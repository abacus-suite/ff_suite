from odoo import fields, models


class FfDemandQuotation(models.TransientModel):
    _inherit = 'ff.demand.quotation'

    send_portal_email = fields.Boolean(
        string='E-mail the Link to the Distributor',
        default=True,
        help='E-mail the link to the distributor so they can approve, and later record deliveries, '
             'without logging in.')

    def action_create(self):
        return super(FfDemandQuotation, self.with_context(ff_no_mail=not self.send_portal_email)).action_create()
