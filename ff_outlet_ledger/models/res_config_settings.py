from odoo import fields, models


class ResConfigSettings(models.TransientModel):
    _inherit = 'res.config.settings'

    ff_auto_invoice = fields.Selection(
        [('yes', 'Create and post automatically'), ('no', 'Leave it to the office')],
        string='When a Distributor Accepts an Order', config_parameter='ff_base.auto_invoice', default='yes',
        help="The company's invoice to the distributor, and each outlet's invoice from the distributor, "
             'are created and posted the moment the order is confirmed.')
    ff_invoice_due_days = fields.Integer(
        string='Default Due Days', config_parameter='ff_base.invoice_due_days', default=30,
        help='Used for an invoice whose customer has no credit days or payment terms of its own.')
    ff_invoice_payment_term_id = fields.Many2one(
        'account.payment.term', string='Default Payment Terms', config_parameter='ff_base.invoice_payment_term_id',
        help='Used for a distributor with no payment terms of its own, and for outlets without credit days.')
