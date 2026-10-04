import secrets
from markupsafe import Markup
from odoo import api, fields, models, _
from odoo.exceptions import UserError


class SaleOrder(models.Model):
    _inherit = 'sale.order'

    distributor_portal_token = fields.Char(
        string='Distributor Portal Token',
        default=lambda self: secrets.token_urlsafe(32),
        copy=False,
        index=True,
    )
    distributor_portal_link = fields.Char(
        string='Distributor Portal Link',
        compute='_compute_distributor_portal_link',
        store=True,
        readonly=True,
        copy=False,
    )
    distributor_status = fields.Selection([
        ('pending', 'Pending'),
        ('confirmed', 'Confirmed'),
        ('rejected', 'Rejected'),
    ], string='Distributor Status', default='pending', compute='_compute_distributor_status', store=True, readonly=False, tracking=True, copy=False)

    distributor_portal_status = fields.Selection([
        ('pending', 'Pending'),
        ('confirmed', 'Confirmed'),
        ('rejected', 'Rejected'),
    ], string='Portal Status', compute='_compute_distributor_status', store=True, readonly=False, copy=False)

    distributor_confirmed_date = fields.Datetime(
        string='Distributor Confirmed On',
        readonly=True,
        copy=False,
    )
    distributor_rejected_date = fields.Datetime(
        string='Distributor Rejected On',
        readonly=True,
        copy=False,
    )
    distributor_note = fields.Text(
        string='Distributor Notes',
        readonly=True,
        copy=False,
    )

    @api.depends('state')
    def _compute_distributor_status(self):
        for order in self:
            if not order.distributor_status:
                if order.state in ('sale', 'done'):
                    order.distributor_status = 'confirmed'
                elif order.state == 'cancel':
                    order.distributor_status = 'rejected'
                else:
                    order.distributor_status = 'pending'
            order.distributor_portal_status = order.distributor_status

    @api.depends('partner_id', 'distributor_portal_token')
    def _compute_distributor_portal_link(self):
        base_url = self.env['ir.config_parameter'].sudo().get_param('web.base.url', '')
        if base_url.endswith('/'):
            base_url = base_url[:-1]

        for order in self:
            real_id = order._origin.id or (isinstance(order.id, int) and order.id)
            if real_id and order.distributor_portal_token:
                order.distributor_portal_link = f"{base_url}/distributor/order/{real_id}?token={order.distributor_portal_token}"
            elif real_id and not order.distributor_portal_token:
                token = secrets.token_urlsafe(32)
                order.distributor_portal_token = token
                order.distributor_portal_link = f"{base_url}/distributor/order/{real_id}?token={token}"
            else:
                order.distributor_portal_link = False

    @api.model_create_multi
    def create(self, vals_list):
        for vals in vals_list:
            if not vals.get('distributor_portal_token'):
                vals['distributor_portal_token'] = secrets.token_urlsafe(32)
        orders = super().create(vals_list)
        orders.generate_distributor_portal_link()
        return orders

    def write(self, vals):
        res = super().write(vals)
        for order in self:
            if not order.distributor_portal_link or not order.distributor_portal_token:
                order.generate_distributor_portal_link()
        return res

    def generate_distributor_portal_link(self):
        """Generate token and full public URL for distributor portal review."""
        base_url = self.env['ir.config_parameter'].sudo().get_param('web.base.url', '')
        if base_url.endswith('/'):
            base_url = base_url[:-1]

        for order in self:
            real_id = order._origin.id or (isinstance(order.id, int) and order.id)
            if not real_id:
                continue
            if not order.distributor_portal_token:
                order.distributor_portal_token = secrets.token_urlsafe(32)
            order.distributor_portal_link = f"{base_url}/distributor/order/{real_id}?token={order.distributor_portal_token}"
        return True

    def action_send_distributor_portal_mail(self, auto_sent=False):
        """Send email to the distributor with the self-service portal link."""
        self.generate_distributor_portal_link()

        template = self.env.ref(
            'l4e_distributor_portal.mail_template_distributor_portal_invitation',
            raise_if_not_found=False
        )

        for order in self:
            recipient = order.partner_id
            if not recipient.email:
                msg = _("⚠️ Could not send distributor portal link: Distributor '%s' has no email address configured.") % recipient.name
                order.message_post(body=msg, subtype_xmlid='mail.mt_note')
                if not auto_sent:
                    raise UserError(msg)
                continue

            if template:
                template.send_mail(order.id, force_send=True)
            else:
                # Fallback email if template is not found
                subject = _("Order Review & Confirmation: %s - Kumbayah Foods") % order.name
                body_html = f"""
                    <p>Dear {recipient.name},</p>
                    <p>A new order quotation <strong>{order.name}</strong> has been generated for your distribution area.</p>
                    <p>You can review the requested products, adjust quantities based on your stock, and confirm the order directly without logging in:</p>
                    <p style="margin: 20px 0;">
                        <a href="{order.distributor_portal_link}" 
                           style="background-color: #28a745; color: #ffffff; padding: 12px 24px; text-decoration: none; border-radius: 5px; font-weight: bold; display: inline-block;">
                            Review &amp; Confirm Order
                        </a>
                    </p>
                    <p>Thank you,<br/><strong>Kumbayah Foods</strong></p>
                """
                mail = self.env['mail.mail'].sudo().create({
                    'subject': subject,
                    'body_html': body_html,
                    'email_to': recipient.email,
                })
                mail.send()

            portal_link = order.distributor_portal_link
            order.message_post(
                body=Markup(
                    f"<b>✉️ Distributor Portal Link Emailed</b><br/>"
                    f"<b>Distributor:</b> {recipient.name} ({recipient.email})<br/>"
                    f"<b>Link:</b> <a href='{portal_link}' target='_blank'>{portal_link}</a>"
                ),
                message_type='notification',
                subtype_xmlid='mail.mt_note',
            )

        return True

    def _ff_distributor_sent(self):
        """An order sent from the app gets what one made by the office wizard gets.

        The distributor is shown what was asked for beside what they adjusted
        it to, so the original quantities are kept, and they are sent the link.
        """
        result = super()._ff_distributor_sent()
        for order in self:
            for line in order.order_line:
                if not line.original_demanded_qty:
                    line.original_demanded_qty = line.product_uom_qty
            order.generate_distributor_portal_link()
            order.action_send_distributor_portal_mail(auto_sent=True)
        return result

    def action_open_distributor_portal(self):
        """Open the distributor portal in a new tab from the backend form view."""
        self.ensure_one()
        self.generate_distributor_portal_link()
        return {
            'type': 'ir.actions.act_url',
            'url': self.distributor_portal_link,
            'target': 'new',
        }


class SaleOrderLine(models.Model):
    _inherit = 'sale.order.line'

    original_demanded_qty = fields.Float(
        string='Demanded Qty',
        readonly=True,
        copy=False,
        help='Original quantity demanded by outlets before distributor adjustments.',
    )
    distributor_adjusted_qty = fields.Float(
        string='Distributor Adjusted Qty',
        readonly=True,
        copy=False,
        help='Quantity adjusted by the distributor in the self-service portal.',
    )
