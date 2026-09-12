import base64
from datetime import timedelta

from odoo import fields, http
from odoo.http import request

from odoo.addons.ff_base.tools import to_iso

from .clients import visible_client
from .common import ApiError, api_route, body, ok, ref

MAX_LIMIT = 300
STATE_LABELS = {'draft': 'Submitted', 'sent': 'Submitted', 'sale': 'Confirmed', 'cancel': 'Cancelled'}


def product_domain():
    return [('sale_ok', '=', True), ('product_tmpl_id.ff_show_in_app', '=', True)]


def product_data(product):
    return {
        'id': product.id,
        'name': product.display_name,
        'sku': product.product_tmpl_id.ff_sku_code or None,
        'default_code': product.default_code or None,
        'price': product.product_tmpl_id.ff_ptr or product.lst_price,
        'mrp': product.product_tmpl_id.ff_mrp or None,
        'ptr': product.product_tmpl_id.ff_ptr or None,
        'pts': product.product_tmpl_id.ff_pts or None,
        'uom': product.uom_id.name,
        'category': ref(product.categ_id),
        'has_image': bool(product.image_128),
    }


def order_data(order, with_lines=False):
    data = {
        'id': order.id,
        'name': order.name,
        'state': order.state,
        'state_label': STATE_LABELS.get(order.state, order.state),
        'date': to_iso(order.date_order),
        'client': ref(order.partner_id),
        'amount_untaxed': order.amount_untaxed,
        'amount_tax': order.amount_tax,
        'amount_total': order.amount_total,
        'currency': order.currency_id.name,
        'line_count': len(order.order_line),
        'visit_id': order.ff_visit_id.id or None,
    }
    if with_lines:
        data['note'] = order.note and str(order.note) or None
        data['lines'] = [{
            'product': ref(line.product_id),
            'sku': line.product_id.product_tmpl_id.ff_sku_code or None,
            'qty': line.product_uom_qty,
            'price_unit': line.price_unit,
            'discount': line.discount,
            'subtotal': line.price_subtotal,
        } for line in order.order_line if line.product_id]
    return data


class FieldForceOrdersApi(http.Controller):

    @api_route('/api/v1/products', methods=('GET',))
    def products(self, employee, q=None, category_id=None, limit=None, offset=None, **kw):
        Product = request.env['product.product'].sudo()
        domain = product_domain()
        if q:
            domain += ['|', '|', ('name', 'ilike', q), ('default_code', 'ilike', q),
                       ('product_tmpl_id.ff_sku_code', 'ilike', q)]
        if category_id:
            try:
                domain.append(('categ_id', 'child_of', int(category_id)))
            except ValueError:
                raise ApiError('category_id must be a number.')
        try:
            limit = min(int(limit or 100), MAX_LIMIT)
            offset = max(int(offset or 0), 0)
        except ValueError:
            raise ApiError('limit and offset must be numbers.')
        products = Product.search(domain, order='name', limit=limit, offset=offset)
        return ok({'total': Product.search_count(domain), 'products': [product_data(p) for p in products]})

    @api_route('/api/v1/products/categories', methods=('GET',))
    def categories(self, employee, **kw):
        groups = request.env['product.product'].sudo()._read_group(product_domain(), ['categ_id'], ['__count'])
        return ok([dict(ref(categ), count=count) for categ, count in groups if categ])

    @api_route('/api/v1/products/<int:product_id>/image', methods=('GET',))
    def product_image(self, employee, product_id, **kw):
        product = request.env['product.product'].sudo().search(
            product_domain() + [('id', '=', product_id)], limit=1)
        if not product or not product.image_128:
            raise ApiError('No image.', 404, 'not_found')
        return request.make_response(base64.b64decode(product.image_128), headers=[
            ('Content-Type', 'image/png'), ('Cache-Control', 'private, max-age=86400'),
        ])

    @api_route('/api/v1/orders', methods=('POST',))
    def create_order(self, employee, **kw):
        data = body()
        try:
            partner_id = int(data.get('partner_id'))
        except (TypeError, ValueError):
            raise ApiError('partner_id is required.')
        partner = visible_client(employee, partner_id)
        # Companies that sell through distributors collect demand instead of
        # quoting the outlet; the app posts the same body either way.
        flow = request.env['ir.config_parameter'].sudo().get_param('ff_base.order_flow') or 'direct'
        if flow == 'demand' and 'ff.demand' in request.env:
            demand = request.env['ff.demand'].ff_create_from_app(employee, partner, data)
            return ok(demand.ff_app_payload(), status=201)
        order = request.env['sale.order'].ff_create_from_app(employee, partner, data)
        return ok(order_data(order, with_lines=True), status=201)

    @api_route('/api/v1/orders', methods=('GET',))
    def orders(self, employee, partner_id=None, limit=None, **kw):
        domain = [('ff_employee_id', '=', employee.id), ('ff_source', '=', 'app')]
        if partner_id:
            domain.append(('partner_id', '=', int(partner_id)))
        orders = request.env['sale.order'].sudo().search(domain, order='date_order desc',
                                                         limit=min(int(limit or 50), 200))
        return ok([order_data(o) for o in orders])

    @api_route('/api/v1/orders/<int:order_id>', methods=('GET',))
    def order(self, employee, order_id, **kw):
        order = request.env['sale.order'].sudo().browse(order_id).exists()
        allowed = order and (order.ff_employee_id == employee
                             or order.ff_employee_id in employee._ff_subordinates())
        if not allowed:
            raise ApiError('Order not found.', 404, 'not_found')
        return ok(order_data(order, with_lines=True))

    @api_route('/api/v1/orders/summary', methods=('GET',))
    def summary(self, employee, **kw):
        start, end = employee._ff_day_bounds(employee._ff_today())
        orders = request.env['sale.order'].sudo().search([
            ('ff_employee_id', '=', employee.id), ('ff_source', '=', 'app'),
            ('date_order', '>=', start), ('date_order', '<', end), ('state', '!=', 'cancel'),
        ])
        return ok({
            'date': employee._ff_today().isoformat(),
            'count': len(orders),
            'amount_untaxed': sum(orders.mapped('amount_untaxed')),
            'amount_total': sum(orders.mapped('amount_total')),
            'currency': orders[:1].currency_id.name or employee.company_id.currency_id.name,
            'server_time': to_iso(fields.Datetime.now()),
        })

    @api_route('/api/v1/orders/dashboard', methods=('GET',))
    def dashboard(self, employee, period='today', **kw):
        """Order totals, a 7-day bar series and the top moved products."""
        today = employee._ff_today()
        first = {
            'week': today - timedelta(days=today.weekday()),
            'month': today.replace(day=1),
        }.get(period, today)
        start, _unused_end = employee._ff_day_bounds(first)
        _unused_start, end = employee._ff_day_bounds(today)
        Order = request.env['sale.order'].sudo()
        base_domain = [('ff_employee_id', '=', employee.id), ('ff_source', '=', 'app'), ('state', '!=', 'cancel')]
        orders = Order.search(base_domain + [('date_order', '>=', start), ('date_order', '<', end)])

        series = []
        for offset in range(6, -1, -1):
            day = today - timedelta(days=offset)
            day_start, day_end = employee._ff_day_bounds(day)
            day_orders = Order.search(base_domain + [('date_order', '>=', day_start), ('date_order', '<', day_end)])
            series.append({
                'date': day.isoformat(),
                'label': day.strftime('%a'),
                'count': len(day_orders),
                'amount': sum(day_orders.mapped('amount_total')),
            })

        groups = request.env['sale.order.line'].sudo()._read_group(
            [('order_id', 'in', orders.ids), ('product_id', '!=', False)],
            ['product_id'], ['product_uom_qty:sum'])
        top = sorted(groups, key=lambda g: g[1], reverse=True)[:5]
        return ok({
            'period': period if period in ('today', 'week', 'month') else 'today',
            'count': len(orders),
            'amount_untaxed': sum(orders.mapped('amount_untaxed')),
            'amount_total': sum(orders.mapped('amount_total')),
            'currency': orders[:1].currency_id.name or employee.company_id.currency_id.name,
            'series': series,
            'top_products': [{
                'id': product.id,
                'name': product.display_name,
                'sku': product.product_tmpl_id.ff_sku_code or None,
                'qty': quantity,
            } for product, quantity in top],
        })
