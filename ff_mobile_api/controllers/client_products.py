"""What a customer has taken from us, product by product.

The list answers "which of our products does this outlet buy"; one product
opens every time it was asked for - when, by whom, how much was asked and how
much was quoted.
"""
from odoo import http
from odoo.http import request

from odoo.addons.ff_base.tools import to_iso

from .clients import visible_client
from .common import api_route, ok, ref


def _label(record, field):
    return dict(record._fields[field]._description_selection(request.env)).get(record[field]) or record[field]


def _entries(partner, product_id=None):
    """One entry per document line for this customer (and its sites), newest first."""
    env = request.env
    family = partner.commercial_partner_id
    entries = []
    if 'ff.demand' in env:
        domain = [('demand_id.partner_id', 'child_of', family.id), ('demand_id.state', '!=', 'cancelled'),
                  ('product_id', '!=', False)]
        if product_id:
            domain.append(('product_id', '=', product_id))
        for line in env['ff.demand.line'].sudo().search(domain):
            demand = line.demand_id
            entries.append({
                'kind': 'demand',
                'document_id': demand.id,
                'number': demand.name,
                'date': to_iso(demand.date),
                'product': line.product_id,
                'employee': ref(demand.employee_id),
                'distributor': ref(demand.distributor_id),
                'site': demand.partner_id.display_name if demand.partner_id != family else None,
                'quantity': line.quantity,
                'quoted': line.quoted_quantity,
                'price': line.price_unit,
                'amount': line.subtotal,
                'state': demand.state,
                'state_label': _label(demand, 'state'),
                'foc': bool(getattr(line, 'is_foc', False)),
            })
    if 'sale.order' in env:
        domain = [('order_id.partner_id', 'child_of', family.id), ('order_id.state', '!=', 'cancel'),
                  ('product_id', '!=', False), ('display_type', '=', False)]
        if product_id:
            domain.append(('product_id', '=', product_id))
        for line in env['sale.order.line'].sudo().search(domain):
            order = line.order_id
            entries.append({
                'kind': 'order',
                'document_id': order.id,
                'number': order.name,
                'date': to_iso(order.date_order),
                'product': line.product_id,
                'employee': ref(order.ff_employee_id) if 'ff_employee_id' in order._fields else None,
                'distributor': ref(order.company_id.partner_id),
                'site': order.partner_id.display_name if order.partner_id != family else None,
                'quantity': line.product_uom_qty,
                'quoted': line.product_uom_qty,
                'delivered': line.qty_delivered,
                'price': line.price_unit,
                'amount': line.price_subtotal,
                'state': order.state,
                'state_label': _label(order, 'state'),
                'foc': False,
            })
    entries.sort(key=lambda e: e['date'] or '', reverse=True)
    return entries


def _product_ref(product):
    return {
        'id': product.id,
        'name': product.display_name,
        'sku': product.product_tmpl_id.ff_sku_code or product.default_code or None,
        'category': product.categ_id.name or None,
        'uom': product.uom_id.name or None,
    }


class FieldForceClientProductsApi(http.Controller):

    @api_route('/api/v1/clients/<int:partner_id>/products', methods=('GET',))
    def products(self, employee, partner_id, **kw):
        partner = visible_client(employee, partner_id)
        rows = {}
        for entry in _entries(partner):
            product = entry['product']
            row = rows.setdefault(product.id, dict(_product_ref(product), times=0, quantity=0.0, quoted=0.0,
                                                   amount=0.0, first_date=entry['date'], last_date=entry['date'],
                                                   last_quantity=entry['quantity'], last_employee=entry['employee']))
            row['times'] += 1
            row['quantity'] += entry['quantity']
            row['quoted'] += entry['quoted'] or 0.0
            row['amount'] += entry['amount']
            row['first_date'] = entry['date']  # entries run newest first, so the last one seen is the oldest
        products = sorted(rows.values(), key=lambda r: r['last_date'] or '', reverse=True)
        for row in products:
            row['amount'] = round(row['amount'], 2)
        return ok({
            'client': {'id': partner.id, 'name': partner.display_name},
            'currency': request.env.company.currency_id.name,
            'products': products,
            'total_amount': round(sum(r['amount'] for r in products), 2),
        })

    @api_route('/api/v1/clients/<int:partner_id>/products/<int:product_id>', methods=('GET',))
    def product(self, employee, partner_id, product_id, **kw):
        partner = visible_client(employee, partner_id)
        entries = _entries(partner, product_id)
        product = request.env['product.product'].sudo().browse(product_id).exists()
        history = [{k: v for k, v in entry.items() if k != 'product'} for entry in entries]
        for row in history:
            row['amount'] = round(row['amount'], 2)
        return ok({
            'client': {'id': partner.id, 'name': partner.display_name},
            'product': _product_ref(product) if product else {'id': product_id, 'name': 'Product'},
            'currency': request.env.company.currency_id.name,
            'times': len(history),
            'quantity': sum(r['quantity'] for r in history),
            'quoted': sum(r['quoted'] or 0.0 for r in history),
            'amount': round(sum(r['amount'] for r in history), 2),
            'history': history,
        })
