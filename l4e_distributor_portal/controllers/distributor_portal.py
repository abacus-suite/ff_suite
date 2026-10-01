from markupsafe import Markup
from odoo import fields, http
from odoo.http import request


class DistributorPortalController(http.Controller):

    @http.route(
        '/distributor/order/<int:order_id>',
        type='http',
        auth='public',
        website=True,
    )
    def view_distributor_order(self, order_id, token=None, **kw):
        """Portal view allowing the distributor to review and adjust quantities."""
        order = request.env['sale.order'].sudo().browse(order_id).exists()

        if not order or not token or token != order.distributor_portal_token:
            return request.render('l4e_distributor_portal.distributor_invalid_token_template', {
                'message': 'This order link is invalid, expired, or unauthorized.'
            })

        is_confirmed = (
            order.state in ('sale', 'done')
            or order.distributor_portal_status == 'confirmed'
        )

        return request.render(
            'l4e_distributor_portal.distributor_portal_order_page',
            {
                'order': order,
                'token': token,
                'is_confirmed': is_confirmed,
                'already_confirmed_msg': kw.get('confirmed') == '1',
            }
        )

    @http.route(
        '/distributor/order/submit',
        type='http',
        auth='public',
        website=True,
        methods=['POST'],
        csrf=False,
    )
    def submit_distributor_order(self, **post):
        """Handle distributor quantity adjustments and confirmation."""
        order_id = int(post.get('order_id') or 0)
        token = post.get('token')

        order = request.env['sale.order'].sudo().browse(order_id).exists()
        if not order or not token or token != order.distributor_portal_token:
            return request.render('l4e_distributor_portal.distributor_invalid_token_template', {
                'message': 'Unauthorized submission or invalid session token.'
            })

        # Prevent double-confirmation
        if order.state in ('sale', 'done') or order.distributor_portal_status == 'confirmed':
            return request.redirect(f'/distributor/order/{order.id}?token={token}&confirmed=1')

        line_ids = request.httprequest.form.getlist('line_ids[]')
        notes = (post.get('notes') or '').strip()

        adjusted_summary = []
        for line_id_str in line_ids:
            try:
                line_id = int(line_id_str)
            except (TypeError, ValueError):
                continue

            line = order.order_line.filtered(lambda l: l.id == line_id)
            if not line:
                continue

            qty_str = post.get(f'qty_{line_id}')
            try:
                new_qty = float(qty_str)
                new_qty = max(0.0, new_qty)
            except (TypeError, ValueError):
                new_qty = line.product_uom_qty

            old_qty = line.product_uom_qty
            if abs(new_qty - old_qty) > 0.001:
                demanded = line.original_demanded_qty or old_qty
                adjusted_summary.append(
                    f"• {line.product_id.display_name}: Demanded {demanded} → Adjusted to {new_qty}"
                )

            line.sudo().write({
                'product_uom_qty': new_qty,
                'distributor_adjusted_qty': new_qty,
            })

        # Update order status and timestamp
        now = fields.Datetime.now()
        order.sudo().write({
            'distributor_portal_status': 'confirmed',
            'distributor_confirmed_date': now,
            'distributor_note': notes or False,
        })

        # Confirm the Sale Order
        if order.state in ('draft', 'sent'):
            order.sudo().action_confirm()

        # Refresh linked Outlet Demands
        demands = request.env['ff.demand'].sudo().search([('order_ids', 'in', order.ids)])
        if demands:
            demands._ff_refresh_state()

        # Post audit note to Sale Order chatter
        adjust_html = (
            "<br/><b>Adjusted Quantities:</b><br/>" + "<br/>".join(adjusted_summary)
        ) if adjusted_summary else "<br/><i>All demanded quantities accepted as quoted.</i>"
        notes_html = f"<br/><b>Distributor Notes:</b> {notes}" if notes else ""

        chatter_body = Markup(
            f"<b>✅ Order Confirmed by Distributor via Portal</b><br/>"
            f"<b>Distributor:</b> {order.partner_id.name}<br/>"
            f"<b>Confirmed On:</b> {fields.Datetime.to_string(now)}"
            f"{adjust_html}"
            f"{notes_html}"
        )
        order.sudo().message_post(
            body=chatter_body,
            message_type='notification',
            subtype_xmlid='mail.mt_note',
        )

        return request.redirect(f'/distributor/order/thankyou?order_id={order.id}&token={token}')

    @http.route(
        '/distributor/order/thankyou',
        type='http',
        auth='public',
        website=True,
    )
    def distributor_thankyou(self, order_id=None, token=None, **kw):
        """Success confirmation page."""
        order = request.env['sale.order'].sudo().browse(int(order_id or 0)).exists()
        if not order or not token or token != order.distributor_portal_token:
            return request.render('l4e_distributor_portal.distributor_invalid_token_template', {
                'message': 'Invalid access.'
            })

        return request.render('l4e_distributor_portal.distributor_thankyou_template', {
            'order': order,
            'token': token,
        })
