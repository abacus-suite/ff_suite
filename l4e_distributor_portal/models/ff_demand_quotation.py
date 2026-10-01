from odoo import api, fields, models


class FfDemandQuotation(models.TransientModel):
    _inherit = 'ff.demand.quotation'

    send_portal_email = fields.Boolean(
        string='Send Portal Link to Distributor',
        default=True,
        help='Automatically email the portal link to the distributor so they can review, adjust quantities, and confirm online without logging in.'
    )

    def action_create(self):
        res = super().action_create()

        # Extract created orders from action window domain
        order_ids = []
        if isinstance(res, dict) and 'domain' in res:
            for condition in res['domain']:
                if isinstance(condition, (list, tuple)) and len(condition) == 3:
                    field_name, op, val = condition
                    if field_name == 'id' and op == 'in' and isinstance(val, (list, tuple)):
                        order_ids = list(val)
                        break

        if order_ids:
            orders = self.env['sale.order'].browse(order_ids)
            for order in orders:
                # Record the original demanded quantities on lines
                for line in order.order_line:
                    if not line.original_demanded_qty:
                        line.original_demanded_qty = line.product_uom_qty

                # Automatically send email with self-service portal link if enabled
                if self.send_portal_email:
                    order.action_send_distributor_portal_mail(auto_sent=True)

        return res
