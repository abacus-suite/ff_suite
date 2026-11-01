from markupsafe import Markup
from odoo import fields, http
from odoo.http import request


def _num(value):
    """A whole number without the trailing .0."""
    return int(value) if float(value).is_integer() else value


def portal_lines(order):
    """The order's lines as the page shows them: paid ones and free (FOC) ones, with tax and discount."""
    rows = []
    for line in order.order_line.filtered(lambda l: not l.display_type):
        taxes = getattr(line, 'tax_ids', False) or getattr(line, 'tax_id', False) or []
        rate = sum(t.amount for t in taxes if getattr(t, 'amount_type', 'percent') == 'percent')
        free = bool(getattr(line, 'ff_is_foc', False)) or (line.discount or 0.0) >= 100.0
        demanded = line.original_demanded_qty or line.product_uom_qty
        rows.append({
            'id': line.id,
            'name': line.product_id.display_name or line.name,
            'sku': line.product_id.product_tmpl_id.ff_sku_code if 'ff_sku_code' in line.product_id.product_tmpl_id._fields else '',
            'price': line.price_unit,
            'discount': 100.0 if free else (line.discount or 0.0),
            'tax': rate,
            'free': free,
            'demanded': _num(demanded),
            'qty': _num(line.product_uom_qty),
            'subtotal': line.price_subtotal,
        })
    return rows


def portal_outlets(order):
    """The outlets behind the order, and what each asked for."""
    rows = []
    for demand in order.ff_demand_ids if 'ff_demand_ids' in order._fields else []:
        partner = demand.partner_id
        rows.append({
            'name': partner.display_name,
            'number': demand.name,
            'address': ', '.join(x for x in (partner.street, partner.city, partner.zip) if x),
            'phone': partner.phone or '',
            'items': [{'name': l.product_id.display_name, 'qty': _num(l.quantity),
                       'free': bool(getattr(l, 'is_foc', False))} for l in demand.line_ids],
        })
    return rows


def request_lines(req):
    """What the request page shows: one row per product, added up across the outlets."""
    rows = []
    final = req.state != 'sent'
    for row in req.ff_lines():
        product = row['product']
        qty = row['approved'] if final else row['demanded']
        rows.append({
            'id': row['id'],
            'name': product.display_name,
            'sku': product.product_tmpl_id.ff_sku_code if 'ff_sku_code' in product.product_tmpl_id._fields else '',
            'price': row['price'], 'discount': 100.0 if row['free'] else 0.0, 'tax': row['tax'],
            'free': row['free'], 'uom': row['uom'], 'demanded': _num(row['demanded']), 'qty': _num(qty),
            'subtotal': 0.0 if row['free'] else row['price'] * qty,
        })
    return rows


def request_outlets(req):
    rows = []
    for demand in req.demand_ids:
        partner = demand.partner_id
        rows.append({
            'name': partner.display_name, 'number': demand.name,
            'address': ', '.join(x for x in (partner.street, partner.city, partner.zip) if x),
            'phone': partner.phone or '',
            'items': [{'name': l.product_id.display_name, 'qty': _num(l.quantity),
                       'free': bool(getattr(l, 'is_foc', False))} for l in demand.line_ids],
        })
    return rows


def _request_for(request_id, token):
    req = request.env['ff.demand.request'].sudo().browse(request_id).exists()
    if not req or not token or token != req.distributor_portal_token:
        return None
    return req


INVALID = 'l4e_distributor_portal.distributor_invalid_token_template'


class DistributorRequestController(http.Controller):
    """The approval page for outlet demands: no sale order behind it, and delivery is recorded here."""

    def _page(self, req, token, **extra):
        lines = request_lines(req)
        approved = req.state in ('approved', 'done')
        values = {
            'lines': lines, 'outlets': request_outlets(req), 'order': req, 'token': token,
            'base': '/distributor/request',
            'summary': {
                'paid_count': len([l for l in lines if not l['free']]),
                'free_count': len([l for l in lines if l['free']]),
                'free_units': sum(float(l['qty']) for l in lines if l['free']),
            },
            'is_confirmed': approved, 'is_rejected': req.state == 'rejected',
            'already_confirmed_msg': extra.get('confirmed') == '1',
            'already_rejected_msg': extra.get('rejected') == '1',
            'deliveries': req.ff_deliveries() if approved else [],
            'delivery_saved': extra.get('delivered') == '1',
        }
        return request.render('l4e_distributor_portal.distributor_portal_order_page', values)

    @http.route('/distributor/request/<int:request_id>', type='http', auth='public', website=True)
    def view(self, request_id, token=None, **kw):
        req = _request_for(request_id, token)
        if not req:
            return request.render(INVALID, {'message': 'This link is invalid, expired, or unauthorized.'})
        return self._page(req, token, **kw)

    @http.route('/distributor/request/submit', type='http', auth='public', website=True,
                methods=['POST'], csrf=False)
    def approve(self, **post):
        req = _request_for(int(post.get('order_id') or 0), post.get('token'))
        if not req:
            return request.render(INVALID, {'message': 'Unauthorized submission or invalid session token.'})
        if req.state == 'sent':
            quantities = {}
            for key in request.httprequest.form.getlist('line_ids[]'):
                try:
                    rid = int(key)
                    quantities[rid] = float(post.get('qty_%s' % rid))
                except (TypeError, ValueError):
                    continue
            try:
                req.ff_approve(quantities, post.get('notes'))
            except Exception as error:  # noqa: BLE001 - say it on the page
                return request.render(INVALID, {'message': str(error)})
        return request.redirect('/distributor/request/thankyou?request_id=%s&token=%s' % (req.id, post.get('token')))

    @http.route('/distributor/request/reject', type='http', auth='public', website=True,
                methods=['POST'], csrf=False)
    def reject(self, **post):
        req = _request_for(int(post.get('order_id') or 0), post.get('token'))
        if not req:
            return request.render(INVALID, {'message': 'Unauthorized submission or invalid session token.'})
        if req.state == 'sent':
            req.ff_reject(post.get('notes'))
        return request.redirect('/distributor/request/thankyou?request_id=%s&token=%s&rejected=1' % (
            req.id, post.get('token')))

    @http.route('/distributor/request/deliver', type='http', auth='public', website=True,
                methods=['POST'], csrf=False)
    def deliver(self, **post):
        """Record what was delivered to one outlet; the outlet is billed for it."""
        req = _request_for(int(post.get('request_id') or 0), post.get('token'))
        if not req:
            return request.render(INVALID, {'message': 'Unauthorized submission or invalid session token.'})
        demand = req.demand_ids.filtered(lambda d: d.id == int(post.get('demand_id') or 0))
        if not demand:
            return request.render(INVALID, {'message': 'That outlet is not part of this request.'})
        quantities = {}
        for key, value in post.items():
            if key.startswith('dq_'):
                try:
                    quantities[int(key[3:])] = float(value or 0)
                except ValueError:
                    continue
        try:
            if post.get('close') == '1':
                demand.ff_close_delivery(post.get('note'))
            else:
                demand.ff_record_delivery(quantities, post.get('note'), entered_by=req.partner_id.name)
        except Exception as error:  # noqa: BLE001 - say it on the page
            return request.render(INVALID, {'message': str(error)})
        return request.redirect('/distributor/request/%s?token=%s&delivered=1' % (req.id, post.get('token')))

    @http.route('/distributor/request/thankyou', type='http', auth='public', website=True)
    def thankyou(self, request_id=None, token=None, **kw):
        req = _request_for(int(request_id or 0), token)
        if not req:
            return request.render(INVALID, {'message': 'Invalid access.'})
        return request.render('l4e_distributor_portal.distributor_thankyou_template', {
            'order': req, 'token': token, 'base': '/distributor/request',
            'is_rejected': kw.get('rejected') == '1' or req.state == 'rejected',
            'units': sum(float(l['qty']) for l in request_lines(req)),
        })


class DistributorPortalController(http.Controller):

    @http.route(
        '/distributor/order/<int:order_id>',
        type='http',
        auth='public',
        website=True,
    )
    def view_distributor_order(self, order_id, token=None, **kw):
        """Portal view allowing the distributor to review, adjust quantities, or reject."""
        order = request.env['sale.order'].sudo().browse(order_id).exists()

        if not order or not token or token != order.distributor_portal_token:
            return request.render('l4e_distributor_portal.distributor_invalid_token_template', {
                'message': 'This order link is invalid, expired, or unauthorized.'
            })

        is_confirmed = (
            order.state in ('sale', 'done')
            or order.distributor_status == 'confirmed'
        )
        is_rejected = (
            order.state == 'cancel'
            or order.distributor_status == 'rejected'
        )

        lines = portal_lines(order)
        return request.render(
            'l4e_distributor_portal.distributor_portal_order_page',
            {
                'lines': lines,
                'outlets': portal_outlets(order),
                'summary': {
                    'paid_count': len([l for l in lines if not l['free']]),
                    'free_count': len([l for l in lines if l['free']]),
                    'free_units': sum(float(l['qty']) for l in lines if l['free']),
                },
                'order': order,
                'token': token,
                'is_confirmed': is_confirmed,
                'is_rejected': is_rejected,
                'already_confirmed_msg': kw.get('confirmed') == '1',
                'already_rejected_msg': kw.get('rejected') == '1',
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

        # Prevent action if already confirmed or rejected
        if order.state in ('sale', 'done') or order.distributor_status in ('confirmed', 'rejected'):
            return request.redirect(f'/distributor/order/{order.id}?token={token}')

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

        # Update order status to confirmed
        now = fields.Datetime.now()
        order.sudo().write({
            'distributor_status': 'confirmed',
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
        '/distributor/order/reject',
        type='http',
        auth='public',
        website=True,
        methods=['POST'],
        csrf=False,
    )
    def reject_distributor_order(self, **post):
        """Handle distributor rejection of the order."""
        order_id = int(post.get('order_id') or 0)
        token = post.get('token')

        order = request.env['sale.order'].sudo().browse(order_id).exists()
        if not order or not token or token != order.distributor_portal_token:
            return request.render('l4e_distributor_portal.distributor_invalid_token_template', {
                'message': 'Unauthorized submission or invalid session token.'
            })

        # Prevent action if already confirmed or rejected
        if order.distributor_status in ('confirmed', 'rejected') or order.state in ('sale', 'done'):
            return request.redirect(f'/distributor/order/{order.id}?token={token}')

        notes = (post.get('notes') or '').strip()
        now = fields.Datetime.now()

        order.sudo().write({
            'distributor_status': 'rejected',
            'distributor_rejected_date': now,
            'distributor_note': notes or False,
        })

        # Move the quotation to Cancelled stage
        if order.state != 'cancel':
            try:
                order.sudo()._action_cancel()
            except Exception:
                order.sudo().write({'state': 'cancel'})

        # Refresh linked Outlet Demands and restore quoted quantities
        demands = request.env['ff.demand'].sudo().search([('order_ids', 'in', order.ids)])
        for demand in demands:
            for dline in demand.line_ids:
                matching_lines = order.order_line.filtered(lambda ol: ol.product_id == dline.product_id)
                quoted_to_deduct = sum(matching_lines.mapped('product_uom_qty'))
                if quoted_to_deduct > 0:
                    dline.quoted_quantity = max(0.0, dline.quoted_quantity - quoted_to_deduct)
            demand._ff_refresh_state()

        # Log rejection in Sale Order chatter
        notes_html = f"<br/><b>Rejection Remarks:</b> {notes}" if notes else "<br/><i>No rejection reason entered.</i>"
        chatter_body = Markup(
            f"<b>❌ Order Rejected by Distributor via Portal</b><br/>"
            f"<b>Distributor:</b> {order.partner_id.name}<br/>"
            f"<b>Status:</b> Moved to Cancelled<br/>"
            f"<b>Rejected On:</b> {fields.Datetime.to_string(now)}"
            f"{notes_html}"
        )
        order.sudo().message_post(
            body=chatter_body,
            message_type='notification',
            subtype_xmlid='mail.mt_note',
        )

        return request.redirect(f'/distributor/order/thankyou?order_id={order.id}&token={token}&rejected=1')

    @http.route(
        '/distributor/order/thankyou',
        type='http',
        auth='public',
        website=True,
    )
    def distributor_thankyou(self, order_id=None, token=None, **kw):
        """Status confirmation page (Confirmed or Rejected)."""
        order = request.env['sale.order'].sudo().browse(int(order_id or 0)).exists()
        if not order or not token or token != order.distributor_portal_token:
            return request.render('l4e_distributor_portal.distributor_invalid_token_template', {
                'message': 'Invalid access.'
            })

        is_rejected = kw.get('rejected') == '1' or order.distributor_status == 'rejected'

        return request.render('l4e_distributor_portal.distributor_thankyou_template', {
            'order': order,
            'token': token,
            'is_rejected': is_rejected,
            'units': sum(order.order_line.mapped('product_uom_qty')),
        })
