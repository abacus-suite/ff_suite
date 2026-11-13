import base64
import html
from html import escape
from datetime import timedelta

from odoo import fields, http
from odoo.http import request

from odoo.addons.ff_base.tools import to_iso

from .clients import visible_client
from .common import ApiError, action_time, api_route, body, ok, ref, require_punched_in, scope_members
from .field_data import partner_commercials, partner_is_company_location

MAX_LIMIT = 300
STATE_LABELS = {'draft': 'Submitted', 'sent': 'Submitted', 'sale': 'Confirmed', 'cancel': 'Cancelled'}


def product_domain():
    return [('sale_ok', '=', True), ('product_tmpl_id.ff_show_in_app', '=', True)]


def product_data(product, partner=None):
    price = product.product_tmpl_id.ff_ptr or product.lst_price
    if partner:
        # What this customer pays: a distributor its own price, an outlet its own. Margin pricing,
        # when it is switched on, changes both without this code knowing.
        price = product.ff_distributor_price(partner) if getattr(partner, 'ff_is_distributor', False) else product.ff_field_price(partner)
    return {
        'id': product.id,
        'name': product.display_name,
        'sku': product.product_tmpl_id.ff_sku_code or None,
        'code': product.product_tmpl_id.ff_code() or None,
        'default_code': product.default_code or None,
        'price': price,
        'tax_percent': sum(t.amount for t in product.taxes_id
                           if t.amount_type == 'percent' and t.company_id == request.env.company),
        'tax_names': [t.name for t in product.taxes_id if t.company_id == request.env.company],
        'mrp': product.product_tmpl_id.ff_mrp or None,
        'ptr': product.product_tmpl_id.ff_ptr or None,
        'pts': product.product_tmpl_id.ff_pts or None,
        'uom': product.uom_id.name,
        'category': ref(product.categ_id),
        'has_image': bool(product.image_128),
    }


def order_stage(order):
    """Confirmed, partly delivered, delivered or invoiced: where the office has got to with it."""
    if order.state == 'cancel':
        return 'Cancelled'
    if order.state in ('draft', 'sent'):
        return 'Submitted'
    if getattr(order, 'invoice_status', '') == 'invoiced':
        return 'Invoiced'
    delivery = getattr(order, 'delivery_status', False)
    if delivery == 'full':
        return 'Delivered'
    if delivery in ('partial', 'started'):
        return 'Partly delivered'
    return 'Confirmed'


def order_data(order, with_lines=False):
    data = {
        'kind': 'order',
        'visit_type': order.ff_visit_id.visit_type if (getattr(order, 'ff_visit_id', False) and order.ff_visit_id.visit_type) else 'offsite',
        'delivery_status': order_stage(order),
        'for_demand': bool(getattr(order, 'ff_demand_ids', False)),
        'id': order.id,
        'name': order.name,
        'state': order.state,
        'state_label': STATE_LABELS.get(order.state, order.state),
        'date': to_iso(order.date_order),
        'client': ref(order.ff_outlet_id or order.partner_id),
        'billed_to': ref(order.partner_id) if order.ff_outlet_id else None,
        'distributor': ref(order.partner_id) if order.ff_outlet_id else None,
        'amount_untaxed': order.amount_untaxed,
        'amount_tax': order.amount_tax,
        'amount_total': order.amount_total,
        'currency': order.currency_id.name,
        'line_count': len(order.order_line),
        'quantity_total': sum(order.order_line.mapped('product_uom_qty')),
        # A few products, so the list can show what the order was for.
        'products': [{'id': line.product_id.id, 'name': line.product_id.display_name,
                      'has_image': bool(line.product_id.image_128),
                      'qty': line.product_uom_qty, 'subtotal': line.price_subtotal}
                     for line in order.order_line[:6] if line.product_id],
        'visit_id': order.ff_visit_id.id or None,
        'employee': ref(order.ff_employee_id),
        # Where the distributor has got to with it. These come from the portal
        # module when it is installed, and are simply absent when it is not.
        'distributor_status': getattr(order, 'distributor_status', None) or None,
        'distributor_note': getattr(order, 'distributor_note', None) or None,
        'portal_link': getattr(order, 'distributor_portal_link', None) or None,
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
            'foc': bool(getattr(line, 'ff_is_foc', False)),
            'foc_note': (line.ff_foc_scheme_id.name or line.ff_foc_reason or None) if getattr(line, 'ff_is_foc', False) else None,
        } for line in order.order_line if line.product_id]
    return data




def _order_html(order):
    company = order.company_id
    currency = order.currency_id.symbol or order.currency_id.name or '₹'
    customer = order.partner_id
    employee = order.ff_employee_id or (request.env['hr.employee'].sudo().search([('user_id', '=', order.user_id.id)], limit=1) if order.user_id else None)

    logo_html = ''
    if getattr(company, 'logo', False):
        try:
            logo_bytes = company.logo
            logo_b64 = logo_bytes if isinstance(logo_bytes, str) else logo_bytes.decode('ascii')
            logo_html = '<img src="data:image/png;base64,%s" style="max-height:55px;max-width:180px;object-fit:contain;"/>' % logo_b64
        except Exception:
            logo_html = '<h2 style="margin:0;color:#1B3A7A;font-size:18pt;font-weight:bold;">%s</h2>' % escape(company.name or '')
    else:
        logo_html = '<h2 style="margin:0;color:#1B3A7A;font-size:18pt;font-weight:bold;">%s</h2>' % escape(company.name or '')

    company_addr = ', '.join(filter(None, [company.street, company.street2, company.city, company.zip]))
    cust_addr = ', '.join(filter(None, [customer.street, customer.street2, customer.city, customer.zip])) if customer else ''

    date_str = order.date_order.strftime('%d-%b-%Y %I:%M %p') if order.date_order else ''
    state_label = dict(order._fields['state'].selection).get(order.state, order.state)

    lines_html = []
    idx = 1
    for l in order.order_line:
        if l.display_type:
            continue
        prod_name = escape(l.product_id.display_name or l.name or '')
        sku = escape(getattr(l.product_id.product_tmpl_id, 'ff_sku_code', '') or l.product_id.default_code or '-')
        qty = ('%.2f' % l.product_uom_qty).rstrip('0').rstrip('.')
        uom = escape(l.product_uom.name or 'Pcs')
        rate = '%.2f' % (l.price_unit or 0.0)
        disc = (('%.2f' % l.discount).rstrip('0').rstrip('.') + '%') if (l.discount or 0) > 0 else '-'
        taxes = ', '.join(t.name for t in l.tax_id) if l.tax_id else '-'
        subtotal = '%.2f' % (l.price_subtotal or 0.0)

        lines_html.append("""
            <tr>
                <td style="border:1px solid #cbd5e1;padding:6px 8px;text-align:center;">%d</td>
                <td style="border:1px solid #cbd5e1;padding:6px 8px;"><b>%s</b></td>
                <td style="border:1px solid #cbd5e1;padding:6px 8px;text-align:center;">%s</td>
                <td style="border:1px solid #cbd5e1;padding:6px 8px;text-align:right;">%s %s</td>
                <td style="border:1px solid #cbd5e1;padding:6px 8px;text-align:right;">%s %s</td>
                <td style="border:1px solid #cbd5e1;padding:6px 8px;text-align:center;">%s</td>
                <td style="border:1px solid #cbd5e1;padding:6px 8px;text-align:center;">%s</td>
                <td style="border:1px solid #cbd5e1;padding:6px 8px;text-align:right;font-weight:bold;">%s %s</td>
            </tr>
        """ % (idx, prod_name, sku, qty, uom, currency, rate, disc, taxes, currency, subtotal))
        idx += 1

    total_qty = sum(l.product_uom_qty for l in order.order_line if not l.display_type)
    html_doc = """<!DOCTYPE html>
<html>
<head>
    <meta charset="utf-8"/>
    <title>Sale Order - %(order_name)s</title>
    <style>
        @page { size: A4; margin: 10mm; }
        body { font-family: Arial, Helvetica, sans-serif; color: #1e293b; font-size: 9.5pt; line-height: 1.35; margin: 0; padding: 24px 28px; }
        .page-wrap { width: 100%%; box-sizing: border-box; }
        .header-table { width: 100%%; border-collapse: collapse; margin-bottom: 14px; }
        .cards-table { width: 100%%; border-collapse: collapse; margin-bottom: 14px; }
        .party-card { border: 1px solid #cbd5e1; border-radius: 6px; vertical-align: top; width: 100%%; background: #fff; }
        .party-header { background: #f1f5f9; padding: 6px 10px; font-weight: bold; font-size: 9pt; border-bottom: 1px solid #cbd5e1; color: #334155; }
        .party-body { padding: 8px 10px; }
        .items-table { width: 100%%; border-collapse: collapse; margin-bottom: 14px; }
        .items-table th { background: #1B3A7A; color: #ffffff; border: 1px solid #1B3A7A; padding: 6px 8px; font-size: 9pt; font-weight: bold; }
        .totals-table { width: 320px; border-collapse: collapse; float: right; margin-bottom: 14px; }
        .totals-table td { padding: 5px 8px; border: 1px solid #cbd5e1; font-size: 9pt; }
        .badge { display: inline-block; padding: 3px 8px; border-radius: 10px; font-size: 8.5pt; font-weight: bold; }
        .badge-status { background: #e0e7ff; color: #3730a3; }
        .footer { clear: both; padding-top: 18px; border-top: 1px dashed #cbd5e1; font-size: 8pt; color: #64748b; text-align: center; }
    </style>
</head>
<body>
<div class="page-wrap">
    <table class="header-table">
        <tr>
            <td style="vertical-align:top;width:60%%;">
                %(logo_html)s
                <div style="font-size:8.5pt;color:#475569;margin-top:4px;">
                    %(company_addr)s<br/>
                    %(company_phone)s%(company_vat)s
                </div>
            </td>
            <td style="vertical-align:top;width:40%%;text-align:right;">
                <div style="font-size:16pt;font-weight:900;color:#1B3A7A;letter-spacing:0.5px;">SALE ORDER</div>
                <div style="font-size:12pt;font-weight:bold;color:#0f172a;margin-top:2px;">%(order_name)s</div>
                <div style="margin-top:4px;"><span class="badge badge-status">%(state_label)s</span></div>
                <div style="font-size:8.5pt;color:#475569;margin-top:6px;">
                    <b>Date:</b> %(date_str)s<br/>
                    %(salesperson_row)s%(payment_term_row)s
                </div>
            </td>
        </tr>
    </table>

    <table class="cards-table">
        <tr>
            <td class="party-card">
                <div class="party-header">CUSTOMER / INVOICE TO</div>
                <div class="party-body">
                    <div style="font-size:10pt;font-weight:bold;color:#0f172a;">%(cust_name)s</div>
                    <div style="font-size:8.5pt;color:#475569;margin-top:2px;">
                        %(cust_addr)s<br/>
                        %(cust_contact)s%(cust_vat)s
                    </div>
                </div>
            </td>
        </tr>
    </table>

    <table class="items-table">
        <thead>
            <tr>
                <th style="width:28px;">#</th>
                <th>Product Description</th>
                <th style="width:70px;">SKU</th>
                <th style="width:70px;">Qty</th>
                <th style="width:80px;">Unit Price</th>
                <th style="width:55px;">Disc</th>
                <th style="width:70px;">Taxes</th>
                <th style="width:90px;">Subtotal</th>
            </tr>
        </thead>
        <tbody>
            %(rows_html)s
        </tbody>
    </table>

    <table class="totals-table">
        <tr>
            <td style="background:#f8fafc;font-weight:bold;">Total Ordered Units</td>
            <td style="text-align:right;font-weight:bold;">%(qty_total)s</td>
        </tr>
        <tr>
            <td style="background:#f8fafc;">Untaxed Amount</td>
            <td style="text-align:right;">%(currency)s %(amount_untaxed)s</td>
        </tr>
        <tr>
            <td style="background:#f8fafc;">Taxes</td>
            <td style="text-align:right;">%(currency)s %(amount_tax)s</td>
        </tr>
        <tr style="font-size:10.5pt;background:#f1f5f9;">
            <td style="font-weight:900;color:#1B3A7A;">Total Amount</td>
            <td style="text-align:right;font-weight:900;color:#1B3A7A;">%(currency)s %(amount_total)s</td>
        </tr>
    </table>

    <div style="clear:both;"></div>
    %(note_html)s

    <div class="footer">
        Generated by Field Force &bull; Official Sale Order Document &bull; %(order_name)s
    </div>
</div>
</body>
</html>""" % {
        'order_name': escape(order.name or ''),
        'logo_html': logo_html,
        'company_addr': escape(company_addr),
        'company_phone': ('Phone: ' + escape(company.phone) + '<br/>') if company.phone else '',
        'company_vat': ('GSTIN: ' + escape(company.vat) + '<br/>') if getattr(company, 'vat', False) else '',
        'state_label': escape(state_label),
        'date_str': escape(date_str),
        'salesperson_row': ('<b>Salesperson:</b> ' + escape(employee.name) + '<br/>') if employee else '',
        'payment_term_row': ('<b>Payment Terms:</b> ' + escape(order.payment_term_id.name) + '<br/>') if order.payment_term_id else '',
        'cust_name': escape(customer.name or '-') if customer else '-',
        'cust_addr': escape(cust_addr),
        'cust_contact': ('Phone: ' + escape(customer.phone or getattr(customer, 'mobile', '') or '') + '<br/>') if (customer and (customer.phone or getattr(customer, 'mobile', ''))) else '',
        'cust_vat': ('GSTIN: ' + escape(customer.vat)) if (customer and getattr(customer, 'vat', False)) else '',
        'rows_html': ''.join(lines_html),
        'qty_total': ('%.2f' % total_qty).rstrip('0').rstrip('.'),
        'currency': escape(currency),
        'amount_untaxed': '%.2f' % (order.amount_untaxed or 0.0),
        'amount_tax': '%.2f' % (order.amount_tax or 0.0),
        'amount_total': '%.2f' % (order.amount_total or 0.0),
        'note_html': ('<div style="margin-top:10px;padding:8px;background:#f8fafc;border:1px solid #cbd5e1;border-radius:4px;"><b>Note:</b> ' + escape(order.note) + '</div>') if getattr(order, 'note', False) else '',
    }
    return html_doc


class FieldForceOrdersApi(http.Controller):

    @api_route('/api/v1/products', methods=('GET',))
    def products(self, employee, q=None, category_id=None, limit=None, offset=None, partner_id=None, **kw):
        Product = request.env['product.product'].sudo()
        partner = None
        if partner_id:
            partner = request.env['res.partner'].sudo().browse(int(partner_id)).exists() if str(partner_id).isdigit() else None
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
        commercials = partner_commercials(partner) if partner and not getattr(partner, 'ff_is_distributor', False) else None
        if commercials and commercials.get('price_category'):
            # An outlet is shown the products of its own price category only (149 or 179).
            domain.append(('product_tmpl_id.ff_mrp', '=', float(commercials['price_category'])))
        products = Product.search(domain, order='name', limit=limit, offset=offset)
        return ok({'total': Product.search_count(domain), 'commercials': commercials,
                   'products': [product_data(p, partner) for p in products]})

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
        if partner.ff_category_type == 'lead':
            raise ApiError('A PO can only be raised for an outlet or a distributor, not a lead.', 400, 'invalid')
        require_punched_in(employee, 'take an order', data)
        request.env['ff.visit'].ff_require_visit(employee, partner, action_time(data) if data.get('at') else None)
        # Companies that sell through distributors collect demand instead of
        # quoting the outlet; the app posts the same body either way.
        flow = request.env['ir.config_parameter'].sudo().get_param('ff_base.order_flow') or 'direct'
        is_distributor = partner.ff_is_distributor or partner.ff_category_type == 'distributor'

        # Check if the outlet belongs to a Company Location territory (direct supply from company)
        # Even if the outlet has a distributor linked in 'Supplied by' (ff_distributor_id),
        # Company Location territory outlets are directly supplied by the company via Sale Orders.
        is_company_location = bool(data.get('is_company_location')) or partner_is_company_location(partner, employee)

        is_direct_flow = (flow != 'demand') or is_distributor or is_company_location
        if not is_direct_flow and 'ff.demand' in request.env:
            demand = request.env['ff.demand'].ff_create_from_app(employee, partner, data)
            return ok(demand.ff_app_payload(), status=201)

        # For company location outlets, direct sale order from company to outlet:
        # Ignore any distributor_id passed (even if outlet has 'Supplied by' distributor)
        # so the order is billed directly to the outlet, not a distributor.
        order_payload = dict(data)
        if is_company_location:
            order_payload.pop('distributor_id', None)

        order = request.env['sale.order'].ff_create_from_app(employee, partner, order_payload)
        if (flow == 'demand' and is_distributor) or is_company_location:
            if order.state in ('draft', 'sent'):
                order.sudo().action_confirm()
        return ok(order_data(order, with_lines=True), status=201)

    @api_route('/api/v1/distributors', methods=('GET',))
    def distributors(self, employee, q=None, partner_id=None, **kw):
        """Who can supply an outlet or be visited/sampled: genuine distributors scoped to the employee."""
        Partner = request.env['res.partner'].sudo()
        domain = [
            ('active', '=', True),
            ('parent_id', '=', False),
            ('company_id', 'in', (False, employee.company_id.id)),
            ('ff_approval_state', '!=', 'rejected'),
            '|', ('ff_category_type', '=', 'distributor'),
            '&', ('ff_is_distributor', '=', True),
                 ('ff_category_type', 'not in', ('outlet', 'customer', 'lead', 'other')),
        ]
        if q:
            domain += ['|', ('name', 'ilike', q), ('city', 'ilike', q)]
        emp = employee.sudo()
        team = emp._ff_subordinates()
        # "mode" tells Manager Mode (the person's team) from employee mode (a manager too: only their own).
        team_view = kw.get('mode') == 'manager' and bool(team)
        # What the secondary-territory chips of each row are narrowed to (the person's own territories).
        emp_terr_ids, emp_dist_ids = set(), set()
        scoped = getattr(emp, 'ff_access_scope', None) != 'all'
        if scoped:
            if getattr(emp, 'ff_allocated_distributors', False) and not team_view:
                # "Allocated Distributors": only the ones with their name on them.
                domain.append(('ff_employee_ids', 'in', [emp.id]))
            else:
                # The distributors of their primary and secondary territories (a manager's team view adds the
                # team's); nobody with no territory is offered somebody else's.
                people = (emp | team) if team_view else emp
                territories = people.mapped('ff_territory_ids')
                if 'ff_secondary_territory' in emp._fields:
                    territories |= people.mapped('ff_secondary_territory')
                emp_terr_ids = set(territories.ids)
                if not territories:
                    domain.append(('id', '=', 0))
                else:
                    places = [('ff_territory_id', 'in', territories.ids)]
                    if 'ff_secondary_territory_ids' in Partner._fields:
                        places = ['|'] + places + [('ff_secondary_territory_ids', 'in', territories.ids)]
                    domain += places
        # A Territory chosen on the form (onboarding): only the distributors of that District / Territory.
        if kw.get('territory_id'):
            tid = int(kw['territory_id'])
            domain += ['|', ('ff_district_id', '=', tid), ('ff_secondary_district_ids', 'in', [tid])]
        rows = Partner.search(domain, order='name', limit=200)

        suggested = Partner.browse()
        if partner_id:
            outlet = Partner.browse(int(partner_id)).exists()
            if outlet and partner_is_company_location(outlet, employee):
                # Outlets in company location territories are supplied directly by the company; no distributor is needed.
                return ok({
                    'suggested_id': None,
                    'distributors': [],
                })
            suggested = outlet.ff_distributor_id if 'ff_distributor_id' in outlet._fields else Partner.browse()
            if not suggested and 'ff_route_ids' in outlet._fields:
                routes = outlet.ff_route_ids.filtered(lambda r: 'ff_distributor_id' in r._fields
                                                      and r.ff_distributor_id)
                suggested = routes[:1].ff_distributor_id if routes else Partner.browse()
            if not suggested:
                outlet_terr_ids = set()
                if 'ff_territory_id' in outlet._fields and outlet.ff_territory_id:
                    outlet_terr_ids.add(outlet.ff_territory_id.id)
                if 'territory_id' in outlet.ff_route_ids._fields:
                    outlet_terr_ids.update(outlet.ff_route_ids.mapped('territory_id').ids)
                for row in rows:
                    r_terrs = set()
                    if 'ff_territory_id' in row._fields and row.ff_territory_id:
                        r_terrs.add(row.ff_territory_id.id)
                    if 'ff_secondary_territory_ids' in row._fields:
                        r_terrs.update(row.ff_secondary_territory_ids.ids)
                    if r_terrs & outlet_terr_ids:
                        suggested = row
                        break
            if not suggested:
                outlet_dist_ids = set()
                if 'ff_district_id' in outlet._fields and outlet.ff_district_id:
                    outlet_dist_ids.add(outlet.ff_district_id.id)
                if 'district_id' in outlet.ff_route_ids._fields:
                    outlet_dist_ids.update(outlet.ff_route_ids.mapped('district_id').ids)
                for row in rows:
                    r_dists = set()
                    if 'ff_district_id' in row._fields and row.ff_district_id:
                        r_dists.add(row.ff_district_id.id)
                    if 'ff_secondary_district_ids' in row._fields:
                        r_dists.update(row.ff_secondary_district_ids.ids)
                    if r_dists & outlet_dist_ids:
                        suggested = row
                        break

        # The usual distributor comes first, but only when it is one the person may choose.
        if suggested and suggested in rows:
            rows = suggested | (rows - suggested)
        else:
            suggested = Partner.browse()

        def _row_districts(row):
            records = []
            if 'ff_district_id' in row._fields and row.ff_district_id:
                records.append(row.ff_district_id)
            if 'ff_secondary_district_ids' in row._fields and row.ff_secondary_district_ids:
                seen = {x.id for x in records}
                for d in row.ff_secondary_district_ids:
                    if d.id not in seen:
                        seen.add(d.id)
                        records.append(d)
            return [ref(d) for d in records]

        def _row_territories(row):
            records = []
            if 'ff_territory_id' in row._fields and row.ff_territory_id:
                records.append(row.ff_territory_id)
            if 'ff_secondary_territory_ids' in row._fields and row.ff_secondary_territory_ids:
                seen = {x.id for x in records}
                for t in row.ff_secondary_territory_ids:
                    if t.id not in seen:
                        seen.add(t.id)
                        records.append(t)
            return [ref(t) for t in records]

        def _scoped_sec_districts(row):
            if 'ff_secondary_district_ids' not in row._fields:
                return []
            dists = row.ff_secondary_district_ids
            if scoped and emp_dist_ids:
                matching = dists.filtered(lambda d: d.id in emp_dist_ids)
                if matching:
                    dists = matching
            return [ref(d) for d in dists]

        def _scoped_sec_territories(row):
            if 'ff_secondary_territory_ids' not in row._fields:
                return []
            terrs = row.ff_secondary_territory_ids
            if scoped and emp_terr_ids:
                matching = terrs.filtered(lambda t: t.id in emp_terr_ids)
                if matching:
                    terrs = matching
            return [ref(t) for t in terrs]

        payload = [{
            'id': row.id,
            'name': row.name,
            'category_type': 'distributor',
            'is_distributor': True,
            'city': row.city or (row.ff_district_id.name if 'ff_district_id' in row._fields and row.ff_district_id else None),
            'district': ref(row.ff_district_id) if 'ff_district_id' in row._fields else None,
            'secondary_districts': _scoped_sec_districts(row),
            'districts': _row_districts(row),
            'territory': ref(row.ff_territory_id) if 'ff_territory_id' in row._fields else None,
            'secondary_territories': _scoped_sec_territories(row),
            'territories': _row_territories(row),
            'phone': row.phone or None,
            'gst': row.vat or None,
            'email': row.email or None,
        } for row in rows]
        if partner_id or kw.get('with_suggested'):
            return ok({
                'suggested_id': suggested.id or None,
                'distributors': payload,
            })
        return ok(payload)

    @api_route('/api/v1/orders', methods=('GET',))
    def orders(self, employee, partner_id=None, limit=None, member=None, start=None, end=None, q=None, **kw):
        people, _label = scope_members(employee, member)
        domain = [('ff_employee_id', 'in', people.ids), ('ff_source', '=', 'app')]
        if partner_id:
            domain.append(('partner_id', '=', int(partner_id)))
        if q:
            domain += ['|', '|', ('name', 'ilike', q), ('partner_id.name', 'ilike', q),
                       ('order_line.product_id.name', 'ilike', q)]
        if start or end:
            try:
                first = fields.Date.to_date(start) if start else fields.Date.to_date(end)
                last = fields.Date.to_date(end) if end else first
            except ValueError:
                raise ApiError('Dates must be YYYY-MM-DD.')
            domain += [('date_order', '>=', employee._ff_day_bounds(min(first, last))[0]),
                       ('date_order', '<', employee._ff_day_bounds(max(first, last))[1])]
        orders = request.env['sale.order'].sudo().search(domain, order='date_order desc',
                                                         limit=min(int(limit or 200), 1000))
        return ok([order_data(o) for o in orders])

    @api_route('/api/v1/orders/<int:order_id>', methods=('GET',))
    def order(self, employee, order_id, **kw):
        order = request.env['sale.order'].sudo().browse(order_id).exists()
        allowed = order and (order.ff_employee_id == employee
                             or order.ff_employee_id in employee._ff_subordinates())
        if not allowed:
            raise ApiError('Order not found.', 404, 'not_found')
        return ok(order_data(order, with_lines=True))

    @api_route('/api/v1/orders/<int:order_id>/pdf', methods=('GET',))
    def order_pdf(self, employee, order_id, **kw):
        """Generates and downloads the Sale Order PDF."""
        order = request.env['sale.order'].sudo().browse(order_id).exists()
        allowed = order and (order.ff_employee_id == employee
                             or order.ff_employee_id in employee._ff_subordinates()
                             or order.user_id == employee.user_id
                             or not order.ff_employee_id
                             or employee.user_id.has_group('sales_team.group_sale_manager')
                             or employee.user_id.has_group('base.group_system'))
        if not allowed:
            raise ApiError('Order not found.', 404, 'not_found')

        pdf = None
        try:
            report = request.env.ref('sale.action_report_saleorder', raise_if_not_found=False)
            if report:
                pdf, _kind = report.sudo()._render_qweb_pdf(report.report_name, res_ids=order.ids)
        except Exception:
            pdf = None

        if not pdf:
            try:
                html = _order_html(order)
                pdf = request.env['ir.actions.report'].sudo()._run_wkhtmltopdf([html])
            except Exception as error:
                raise ApiError('Failed to generate Sale Order PDF: %s' % error, 500, 'pdf_error')

        name = 'Order_%s.pdf' % (order.name or order_id).replace('/', '_')
        return request.make_response(pdf, headers=[
            ('Content-Type', 'application/pdf'),
            ('Content-Length', len(pdf)),
            ('Content-Disposition', 'attachment; filename="%s"' % name),
        ])

    @api_route('/api/v1/orders/summary', methods=('GET',))
    def summary(self, employee, member=None, start=None, end=None, **kw):
        people, _label = scope_members(employee, member)
        today = employee._ff_today()
        try:
            first = fields.Date.to_date(start) if start else today
            last = fields.Date.to_date(end) if end else first
        except ValueError:
            raise ApiError('Dates must be YYYY-MM-DD.')
        first, last = min(first, last), max(first, last)
        start, _unused = employee._ff_day_bounds(first)
        _unused2, end = employee._ff_day_bounds(last)
        env = request.env
        flow = env['ir.config_parameter'].sudo().get_param('ff_base.order_flow') or 'direct'
        if flow == 'demand' and 'ff.demand' in env:
            # A demand carries the product's sales taxes, so its value is what the outlet will be billed.
            demands = env['ff.demand'].sudo().search([
                ('employee_id', 'in', people.ids), ('date', '>=', start), ('date', '<', end),
                ('state', '!=', 'cancelled')])
            total = sum(demands.mapped('amount_total'))
            return ok({
                'date': employee._ff_today().isoformat(),
                'flow': 'demand',
                'count': len(demands),
                'amount_untaxed': sum(demands.mapped('amount_untaxed')),
                'amount_tax': sum(demands.mapped('amount_tax')),
                'amount_total': total,
                'currency': demands[:1].currency_id.name or employee.company_id.currency_id.name,
                'server_time': to_iso(fields.Datetime.now()),
            })
        orders = env['sale.order'].sudo().search([
            ('ff_employee_id', 'in', people.ids), ('ff_source', '=', 'app'),
            ('date_order', '>=', start), ('date_order', '<', end), ('state', '!=', 'cancel'),
        ])
        return ok({
            'flow': 'direct',
            'date': employee._ff_today().isoformat(),
            'count': len(orders),
            'amount_untaxed': sum(orders.mapped('amount_untaxed')),
            'amount_total': sum(orders.mapped('amount_total')),
            'currency': orders[:1].currency_id.name or employee.company_id.currency_id.name,
            'server_time': to_iso(fields.Datetime.now()),
        })

    def _hourly(self, employee, orders, date_field='date_order', other=None, other_field='date_order'):
        """Order value by hour of the working day, in the employee's timezone.

        ``other`` is a second set (distributor orders) charted beside the first.
        """
        buckets = {hour: 0.0 for hour in range(9, 20, 2)}
        second = {hour: 0.0 for hour in range(9, 20, 2)}
        for source, field, target in ((orders, date_field, buckets), (other or [], other_field, second)):
            for order in source:
                local = employee._ff_to_local(order[field])
                hour = min(max(local.hour - (local.hour % 2), 9), 19)
                target[hour] = target.get(hour, 0.0) + order.amount_total
        return [{
            'hour': hour,
            'label': '%d%s' % (hour if hour <= 12 else hour - 12, 'AM' if hour < 12 else 'PM'),
            'amount': round(buckets.get(hour, 0.0), 2),
            'outlet': round(buckets.get(hour, 0.0), 2),
            'distributor': round(second.get(hour, 0.0), 2),
        } for hour in sorted(set(buckets) | set(second))]

    @api_route('/api/v1/orders/dashboard', methods=('GET',))
    def dashboard(self, employee, period='today', member=None, **kw):
        """Sales totals, a 7-day series and the top moved products.

        On the demand flow the field takes demands, not sale orders, so the
        figures come from demands; otherwise from the orders taken in the app.
        """
        env = request.env
        people, _label = scope_members(employee, member)
        today = employee._ff_today()
        first = {
            'week': today - timedelta(days=today.weekday()),
            'month': today.replace(day=1),
        }.get(period, today)
        start, _unused_end = employee._ff_day_bounds(first)
        _unused_start, end = employee._ff_day_bounds(today)
        flow = env['ir.config_parameter'].sudo().get_param('ff_base.order_flow') or 'direct'
        demand = flow == 'demand' and 'ff.demand' in env
        if demand:
            Model, date_field = env['ff.demand'].sudo(), 'date'
            base_domain = [('employee_id', 'in', people.ids), ('state', '!=', 'cancelled')]
        else:
            Model, date_field = env['sale.order'].sudo(), 'date_order'
            base_domain = [('ff_employee_id', 'in', people.ids), ('ff_source', '=', 'app'), ('state', '!=', 'cancel')]

        def between(low, high):
            return Model.search(base_domain + [(date_field, '>=', low), (date_field, '<', high)])

        orders = between(start, end)

        # Distributor orders are direct sale orders; they are charted beside the outlet demands.
        dist_domain = [('ff_employee_id', 'in', people.ids), ('ff_source', '=', 'app'), ('state', '!=', 'cancel')]
        if demand and 'ff_demand_ids' in env['sale.order']._fields:
            dist_domain.append(('ff_demand_ids', '=', False))

        def dist_between(low, high):
            if not demand:
                return env['sale.order']
            return env['sale.order'].sudo().search(dist_domain + [('date_order', '>=', low), ('date_order', '<', high)])

        dist_orders = dist_between(start, end)

        series = []
        for offset in range(6, -1, -1):
            day = today - timedelta(days=offset)
            bounds = employee._ff_day_bounds(day)
            day_orders = between(*bounds)
            series.append({
                'outlet': sum(day_orders.mapped('amount_total')),
                'distributor': sum(dist_between(*bounds).mapped('amount_total')),
                'date': day.isoformat(),
                'label': day.strftime('%a'),
                'count': len(day_orders),
                'amount': sum(day_orders.mapped('amount_total')),
            })

        if demand:
            groups = env['ff.demand.line'].sudo()._read_group(
                [('demand_id', 'in', orders.ids), ('product_id', '!=', False)], ['product_id'], ['quantity:sum', 'price_total:sum'])
        else:
            groups = env['sale.order.line'].sudo()._read_group(
                [('order_id', 'in', orders.ids), ('product_id', '!=', False)], ['product_id'], ['product_uom_qty:sum', 'price_total:sum'])
        top = sorted(groups, key=lambda g: g[1], reverse=True)[:5]

        # The same stretch of time, one period earlier, so the app can say
        # "+28% against yesterday" rather than showing a number with no scale.
        span = (today - first).days + 1
        prev_from, _unused = employee._ff_day_bounds(first - timedelta(days=span))
        prev_to, _unused2 = employee._ff_day_bounds(first)
        previous = between(prev_from, prev_to)

        def change(now, before):
            if not before:
                return 100.0 if now else 0.0
            return round((now - before) / float(before) * 100.0, 1)

        total = sum(orders.mapped('amount_total'))
        return ok({
            'period': period if period in ('today', 'week', 'month') else 'today',
            'flow': 'demand' if demand else 'direct',
            'count': len(orders),
            'amount_untaxed': sum(orders.mapped('amount_untaxed')),
            'amount_total': total,
            'currency': orders[:1].currency_id.name or employee.company_id.currency_id.name,
            'previous': {
                'count': len(previous),
                'amount_total': sum(previous.mapped('amount_total')),
                'count_change': change(len(orders), len(previous)),
                'amount_change': change(total, sum(previous.mapped('amount_total'))),
            },
            'hours': self._hourly(employee, orders, date_field, dist_orders, 'date_order'),
            'distributor_amount': sum(dist_orders.mapped('amount_total')),
            'distributor_count': len(dist_orders),
            'series': series,
            'top_products': [{
                'id': product.id,
                'name': product.display_name,
                'sku': product.product_tmpl_id.ff_sku_code or None,
                'code': product.product_tmpl_id.ff_code() or None,
                'has_image': bool(product.image_128),
                'qty': quantity,
                'amount': round(value or 0.0, 2),
            } for product, quantity, value in top],
        })
