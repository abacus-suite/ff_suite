"""Demand endpoints, and the switch that decides what an app order becomes."""
import html
from html import escape
import re

from odoo import fields, http
from odoo.http import request

from odoo.addons.ff_base.tools import to_iso
from odoo.addons.ff_mobile_api.controllers.clients import to_int, visible_client
from odoo.addons.ff_mobile_api.controllers.common import (
    ApiError, action_time, api_route, body, ok, ref, require_punched_in, scope_members)

from ..models.ff_demand import order_flow

STATE_LABELS = {
    'draft': 'Draft',
    'submitted': 'Submitted',
    'waiting': 'Waiting for distributor',
    'approved': 'Approved',
    'rejected': 'Rejected',
    'quoted': 'Sent to distributor',
    'partial': 'Partly sent',
    'supplied': 'Delivered',
    'cancelled': 'Cancelled',
}


def _digits(value):
    return re.sub(r'\D', '', value or '') or None


def _distributor(partner):
    """A distributor as the app needs it: who, and the number to message."""
    data = ref(partner)
    if data:
        data['phone'] = _digits(partner.phone or getattr(partner, 'mobile', ''))
    return data


def demand_data(demand, with_lines=False):
    data = {
        'id': demand.id,
        'name': demand.name,
        'kind': 'demand',
        'visit_type': demand.visit_id.visit_type if (demand.visit_id and demand.visit_id.visit_type) else 'offsite',
        'visit_id': demand.visit_id.id or None,
        'client': ref(demand.partner_id),
        'employee': ref(demand.employee_id),
        'distributor': _distributor(demand.distributor_id),
        'distributor_mapped': bool(demand.distributor_id),
        'quantity_total': demand.quantity_total,
        'date': to_iso(demand.date),
        'amount_untaxed': demand.amount_untaxed,
        'amount_tax': demand.amount_tax,
        'amount_total': demand.amount_total,
        'currency': demand.currency_id.name,
        'state': demand.state,
        'state_label': STATE_LABELS.get(demand.state, demand.state),
        'quoted_percent': demand.quoted_ratio,
        'delivery_status': demand.delivery_status_id.name or None,
        'delivery_code': demand.delivery_status_id.code or None,
        'approved_qty': demand.approved_quantity,
        'delivered_qty': demand.delivered_quantity,
        'delivered_amount': demand.delivered_amount,
        'reject_note': demand.reject_note or None,
        'request': {'id': demand.request_id.id, 'name': demand.request_id.name,
                    'state': demand.request_id.state,
                    'portal_link': getattr(demand.request_id, 'distributor_portal_link', None) or None}
        if demand.request_id else None,
        'note': demand.note or None,
        'route': ref(demand.route_id),
        'foc_status': getattr(demand, 'foc_status', None) or None,
        'foc_only': bool(getattr(demand, 'foc_status', None)) and not demand._ff_paid_lines(),
    }
    if with_lines == 'brief':
        # Just enough for grouping by product in the list.
        data['products'] = [{'id': line.product_id.id, 'name': line.product_id.display_name,
                             'has_image': bool(line.product_id.image_128),
                             'qty': line.quantity, 'subtotal': line.subtotal}
                            for line in demand.line_ids if line.product_id]
    elif with_lines:
        from odoo.addons.ff_mobile_api.controllers.orders import order_data
        data['orders'] = [order_data(order) for order in demand.order_ids.sorted('id', reverse=True)]
        data['deliveries'] = [{
            'id': d.id, 'name': d.name, 'date': to_iso(d.date), 'amount': d.amount, 'by': d.entered_by or None,
            'note': d.note or None,
            'lines': [{'product': l.product_id.display_name, 'qty': l.quantity} for l in d.line_ids],
        } for d in demand.delivery_ids]
        data['lines'] = [{
            'product': ref(line.product_id),
            'sku': line.product_id.product_tmpl_id.ff_sku_code or None,
            'uom': line.uom_id.name or None,
            'qty': line.quantity,
            'quoted_qty': line.quoted_quantity,
            'approved_qty': line.approved_quantity,
            'delivered_qty': line.delivered_quantity,
            'price_unit': line.price_unit,
            'subtotal': line.subtotal,
            'tax_percent': line.tax_percent,
            'price_tax': line.price_tax,
            'foc': bool(getattr(line, 'is_foc', False)),
            'discount': getattr(line, 'discount', 0.0),
            'foc_note': (line.foc_scheme_id.name or line.foc_reason or None) if getattr(line, 'is_foc', False) else None,
        } for line in demand.line_ids]
    # The credit / debit notes raised with the demand (a module that has them adds this).
    if with_lines and hasattr(demand, 'ff_notes_payload'):
        data['notes'] = demand.ff_notes_payload()
    return data




def _demand_html(demand):
    company = demand.company_id
    currency = demand.currency_id.symbol or demand.currency_id.name or '₹'
    outlet = demand.partner_id
    distributor = demand.distributor_id
    employee = demand.employee_id

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
    outlet_addr = ', '.join(filter(None, [outlet.street, outlet.street2, outlet.city, outlet.zip])) if outlet else ''
    dist_addr = ', '.join(filter(None, [distributor.street, distributor.street2, distributor.city, distributor.zip])) if distributor else ''

    date_str = demand.date.strftime('%d-%b-%Y %I:%M %p') if demand.date else ''
    state_label = STATE_LABELS.get(demand.state, demand.state)

    lines_html = []
    for idx, l in enumerate(demand.line_ids, 1):
        prod_name = escape(l.product_id.display_name or '')
        sku = escape(getattr(l.product_id.product_tmpl_id, 'ff_sku_code', '') or l.product_id.default_code or '-')
        qty = ('%.2f' % l.quantity).rstrip('0').rstrip('.')
        uom = escape(l.uom_id.name or 'Pcs')
        rate = '%.2f' % (l.price_unit or 0.0)
        is_foc = bool(getattr(l, 'is_foc', False))
        foc_badge = '<span style="background:#e0f2fe;color:#0369a1;padding:2px 5px;border-radius:4px;font-size:8pt;font-weight:bold;">FOC</span>' if is_foc else '-'
        tax_pct = ('%.2f' % (l.tax_percent or 0.0)).rstrip('0').rstrip('.') + '%' if (l.tax_percent or 0) > 0 else '0%'
        tax_amt = '%.2f' % (l.price_tax or 0.0)
        subtotal = '%.2f' % (l.subtotal or 0.0)

        lines_html.append("""
            <tr>
                <td style="border:1px solid #cbd5e1;padding:6px 8px;text-align:center;">%d</td>
                <td style="border:1px solid #cbd5e1;padding:6px 8px;"><b>%s</b></td>
                <td style="border:1px solid #cbd5e1;padding:6px 8px;text-align:center;">%s</td>
                <td style="border:1px solid #cbd5e1;padding:6px 8px;text-align:right;">%s %s</td>
                <td style="border:1px solid #cbd5e1;padding:6px 8px;text-align:right;">%s %s</td>
                <td style="border:1px solid #cbd5e1;padding:6px 8px;text-align:center;">%s</td>
                <td style="border:1px solid #cbd5e1;padding:6px 8px;text-align:right;">%s</td>
                <td style="border:1px solid #cbd5e1;padding:6px 8px;text-align:right;">%s %s</td>
                <td style="border:1px solid #cbd5e1;padding:6px 8px;text-align:right;font-weight:bold;">%s %s</td>
            </tr>
        """ % (idx, prod_name, sku, qty, uom, currency, rate, foc_badge, tax_pct, currency, tax_amt, currency, subtotal))

    html_doc = """<!DOCTYPE html>
<html>
<head>
    <meta charset="utf-8"/>
    <title>Demand - %(demand_name)s</title>
    <style>
        @page { size: A4; margin: 10mm; }
        body { font-family: Arial, Helvetica, sans-serif; color: #1e293b; font-size: 9.5pt; line-height: 1.35; margin: 0; padding: 24px 28px; }
        .page-wrap { width: 100%%; box-sizing: border-box; }
        .header-table { width: 100%%; border-collapse: collapse; margin-bottom: 14px; }
        .cards-table { width: 100%%; border-collapse: collapse; margin-bottom: 14px; }
        .party-card { border: 1px solid #cbd5e1; border-radius: 6px; vertical-align: top; width: 48.5%%; background: #fff; }
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
                <div style="font-size:16pt;font-weight:900;color:#1B3A7A;letter-spacing:0.5px;">DEMAND NOTE</div>
                <div style="font-size:12pt;font-weight:bold;color:#0f172a;margin-top:2px;">%(demand_name)s</div>
                <div style="margin-top:4px;"><span class="badge badge-status">%(state_label)s</span></div>
                <div style="font-size:8.5pt;color:#475569;margin-top:6px;">
                    <b>Date:</b> %(date_str)s<br/>
                    <b>Field Rep:</b> %(employee_name)s<br/>
                    %(route_row)s%(visit_row)s
                </div>
            </td>
        </tr>
    </table>

    <table class="cards-table">
        <tr>
            <td class="party-card">
                <div class="party-header">OUTLET / CUSTOMER</div>
                <div class="party-body">
                    <div style="font-size:10pt;font-weight:bold;color:#0f172a;">%(outlet_name)s</div>
                    <div style="font-size:8.5pt;color:#475569;margin-top:2px;">
                        %(outlet_addr)s<br/>
                        %(outlet_contact)s%(outlet_vat)s
                    </div>
                </div>
            </td>
            <td style="width:3%%;"></td>
            <td class="party-card">
                <div class="party-header">SUPPLIED BY (DISTRIBUTOR)</div>
                <div class="party-body">
                    <div style="font-size:10pt;font-weight:bold;color:#0f172a;">%(dist_name)s</div>
                    <div style="font-size:8.5pt;color:#475569;margin-top:2px;">
                        %(dist_addr)s<br/>
                        %(dist_contact)s
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
                <th style="width:80px;">Rate</th>
                <th style="width:50px;">FOC</th>
                <th style="width:55px;">Tax %%</th>
                <th style="width:75px;">Tax</th>
                <th style="width:85px;">Subtotal</th>
            </tr>
        </thead>
        <tbody>
            %(rows_html)s
        </tbody>
    </table>

    <table class="totals-table">
        <tr>
            <td style="background:#f8fafc;font-weight:bold;">Total Demanded Units</td>
            <td style="text-align:right;font-weight:bold;">%(qty_total)s</td>
        </tr>
        <tr>
            <td style="background:#f8fafc;">Untaxed Amount</td>
            <td style="text-align:right;">%(currency)s %(amount_untaxed)s</td>
        </tr>
        <tr>
            <td style="background:#f8fafc;">Tax</td>
            <td style="text-align:right;">%(currency)s %(amount_tax)s</td>
        </tr>
        <tr style="font-size:10.5pt;background:#f1f5f9;">
            <td style="font-weight:900;color:#1B3A7A;">Grand Total</td>
            <td style="text-align:right;font-weight:900;color:#1B3A7A;">%(currency)s %(amount_total)s</td>
        </tr>
    </table>

    <div style="clear:both;"></div>
    %(note_html)s

    <div class="footer">
        Generated by Field Force &bull; Official Demand Record &bull; %(demand_name)s
    </div>
</div>
</body>
</html>""" % {
        'demand_name': escape(demand.name or ''),
        'logo_html': logo_html,
        'company_addr': escape(company_addr),
        'company_phone': ('Phone: ' + escape(company.phone) + '<br/>') if company.phone else '',
        'company_vat': ('GSTIN: ' + escape(company.vat) + '<br/>') if getattr(company, 'vat', False) else '',
        'state_label': escape(state_label),
        'date_str': escape(date_str),
        'employee_name': escape(employee.name or '-'),
        'route_row': ('<b>Beat:</b> ' + escape(demand.route_id.name) + '<br/>') if demand.route_id else '',
        'visit_row': ('<b>Visit:</b> ' + escape(demand.visit_id.visit_type.capitalize()) + '<br/>') if (demand.visit_id and demand.visit_id.visit_type) else '',
        'outlet_name': escape(outlet.name or '-') if outlet else '-',
        'outlet_addr': escape(outlet_addr),
        'outlet_contact': ('Phone: ' + escape(outlet.phone or getattr(outlet, 'mobile', '') or '') + '<br/>') if (outlet and (outlet.phone or getattr(outlet, 'mobile', ''))) else '',
        'outlet_vat': ('GSTIN: ' + escape(outlet.vat) + '<br/>') if (outlet and getattr(outlet, 'vat', False)) else '',
        'dist_name': escape(distributor.name or 'Direct / Unassigned') if distributor else 'Direct / Unassigned',
        'dist_addr': escape(dist_addr),
        'dist_contact': ('Phone: ' + escape(distributor.phone or getattr(distributor, 'mobile', '') or '') + '<br/>') if (distributor and (distributor.phone or getattr(distributor, 'mobile', ''))) else '',
        'rows_html': ''.join(lines_html),
        'qty_total': ('%.2f' % (demand.quantity_total or 0.0)).rstrip('0').rstrip('.'),
        'currency': escape(currency),
        'amount_untaxed': '%.2f' % (demand.amount_untaxed or 0.0),
        'amount_tax': '%.2f' % (demand.amount_tax or 0.0),
        'amount_total': '%.2f' % (demand.amount_total or 0.0),
        'note_html': ('<div style="margin-top:10px;padding:8px;background:#f8fafc;border:1px solid #cbd5e1;border-radius:4px;"><b>Note:</b> ' + escape(demand.note) + '</div>') if demand.note else '',
    }
    return html_doc


class FieldForceDemandApi(http.Controller):

    @api_route('/api/v1/demands', methods=('POST',))
    def create_demand(self, employee, **kw):
        data = body()
        partner = visible_client(employee, to_int(data.get('partner_id')))
        require_punched_in(employee, 'add a demand', data)
        request.env['ff.visit'].ff_require_visit(employee, partner, action_time(data) if data.get('at') else None)
        demand = request.env['ff.demand'].ff_create_from_app(employee, partner, data)
        return ok(demand_data(demand, with_lines=True), status=201)

    @api_route('/api/v1/demands', methods=('GET',))
    def demands(self, employee, partner_id=None, limit=None, member=None, start=None, end=None,
                state=None, q=None, route_id=None, **kw):
        people, _label = scope_members(employee, member)
        domain = [('employee_id', 'in', people.ids)]
        if partner_id:
            domain.append(('partner_id', '=', to_int(partner_id)))
        if route_id:
            domain.append(('route_id', '=', to_int(route_id)))
        if state:
            domain.append(('state', 'in', state.split(',')))
        if q:
            domain += ['|', '|', ('name', 'ilike', q), ('partner_id.name', 'ilike', q),
                       ('line_ids.product_id.name', 'ilike', q)]
        if start or end:
            try:
                low_day = fields.Date.to_date(start) if start else fields.Date.to_date(end)
                high_day = fields.Date.to_date(end) if end else low_day
            except ValueError:
                raise ApiError('Dates must be YYYY-MM-DD.')
            domain += [('date', '>=', employee._ff_day_bounds(min(low_day, high_day))[0]),
                       ('date', '<', employee._ff_day_bounds(max(low_day, high_day))[1])]
        demands = request.env['ff.demand'].sudo().search(
            domain, order='date desc', limit=min(to_int(limit) or 200, 1000))
        return ok([demand_data(demand, with_lines='brief') for demand in demands])

    @api_route('/api/v1/demands/<int:demand_id>', methods=('GET',))
    def demand(self, employee, demand_id, **kw):
        demand = request.env['ff.demand'].sudo().browse(demand_id).exists()
        allowed = demand and (demand.employee_id == employee
                              or demand.employee_id in employee._ff_subordinates())
        if not allowed:
            raise ApiError('Demand not found.', 404, 'not_found')
        return ok(demand_data(demand, with_lines=True))

    @api_route('/api/v1/demands/submit', methods=('POST',))
    def submit_to_distributor(self, employee, **kw):
        """Send the chosen demands to a distributor to be approved: one request, one link."""
        data = body()
        ids = [to_int(value) for value in (data.get('demand_ids') or [])]
        ids = [value for value in ids if value]
        if not ids:
            raise ApiError('Choose the demands to send.')
        demands = request.env['ff.demand'].sudo().browse(ids).exists()
        distributor = request.env['res.partner'].sudo().browse(to_int(data.get('distributor_id')) or 0).exists()
        sent = request.env['ff.demand'].ff_submit_to_distributor(employee, demands, distributor)
        return ok({
            # Kept under "order" so a phone that has not been updated still understands it.
            'order': {'id': sent.id, 'name': sent.name,
                      'portal_link': getattr(sent, 'distributor_portal_link', None) or None},
            'request': {'id': sent.id, 'name': sent.name,
                        'portal_link': getattr(sent, 'distributor_portal_link', None) or None},
            'distributor': _distributor(distributor),
            'demands': [demand_data(demand) for demand in demands],
        }, status=201)

    @api_route('/api/v1/demand-requests/<int:request_id>/resend', methods=('POST',))
    def resend_request(self, employee, request_id, **kw):
        """A request the distributor rejected goes out again, to the same distributor or another."""
        old = request.env['ff.demand.request'].sudo().browse(request_id).exists()
        mine = employee | employee._ff_subordinates()
        if not old or old.ff_employee_id not in mine:
            raise ApiError('Request not found.', 404, 'not_found')
        if old.state != 'rejected':
            raise ApiError('Only a request the distributor rejected can be sent again.', 409, 'conflict')
        chosen = to_int(body().get('distributor_id'))
        distributor = request.env['res.partner'].sudo().browse(chosen or old.partner_id.id).exists()
        demands = old.demand_ids
        sent = request.env['ff.demand'].ff_submit_to_distributor(employee, demands, distributor)
        return ok({
            'order': {'id': sent.id, 'name': sent.name,
                      'portal_link': getattr(sent, 'distributor_portal_link', None) or None},
            'request': {'id': sent.id, 'name': sent.name,
                        'portal_link': getattr(sent, 'distributor_portal_link', None) or None},
            'distributor': _distributor(distributor),
            'demands': [demand_data(demand) for demand in demands],
        }, status=201)

    @api_route('/api/v1/demands/<int:demand_id>/resend', methods=('POST',))
    def resend_demand(self, employee, demand_id, **kw):
        """Send one rejected (or still unsent) demand to a distributor, on its own request."""
        demand = request.env['ff.demand'].sudo().browse(demand_id).exists()
        mine = employee | employee._ff_subordinates()
        if not demand or demand.employee_id not in mine:
            raise ApiError('Demand not found.', 404, 'not_found')
        chosen = to_int(body().get('distributor_id'))
        distributor = request.env['res.partner'].sudo().browse(chosen or demand.distributor_id.id).exists()
        sent = request.env['ff.demand'].ff_submit_to_distributor(employee, demand, distributor)
        return ok({
            'request': {'id': sent.id, 'name': sent.name,
                        'portal_link': getattr(sent, 'distributor_portal_link', None) or None},
            'distributor': _distributor(distributor),
            'demands': [demand_data(demand)],
        }, status=201)

    @api_route('/api/v1/orders/<int:order_id>/resend', methods=('POST',))
    def resend_to_distributor(self, employee, order_id, **kw):
        """The old way: an order a distributor rejected, sent again. Kept for orders made before requests."""
        old = request.env['sale.order'].sudo().browse(order_id).exists()
        mine = employee | employee._ff_subordinates()
        if not old or old.ff_employee_id not in mine:
            raise ApiError('Order not found.', 404, 'not_found')
        if old.state != 'cancel':
            raise ApiError('Only an order the distributor rejected can be sent again.', 409, 'conflict')
        demands = old.ff_demand_ids
        if not demands:
            raise ApiError('This order has no outlet demands to send again.')
        chosen = to_int(body().get('distributor_id'))
        distributor = request.env['res.partner'].sudo().browse(chosen or old.partner_id.id).exists()
        sent = request.env['ff.demand'].ff_submit_to_distributor(employee, demands, distributor)
        return ok({
            'order': {'id': sent.id, 'name': sent.name,
                      'portal_link': getattr(sent, 'distributor_portal_link', None) or None},
            'request': {'id': sent.id, 'name': sent.name,
                        'portal_link': getattr(sent, 'distributor_portal_link', None) or None},
            'distributor': _distributor(distributor),
            'demands': [demand_data(demand) for demand in demands],
        }, status=201)



    @api_route('/api/v1/demands/<int:demand_id>/pdf', methods=('GET',))
    def demand_pdf(self, employee, demand_id, **kw):
        """Generates and downloads the Demand PDF for the given demand."""
        demand = request.env['ff.demand'].sudo().browse(demand_id).exists()
        allowed = demand and (demand.employee_id == employee
                              or demand.employee_id in employee._ff_subordinates()
                              or employee.user_id.has_group('sales_team.group_sale_manager')
                              or employee.user_id.has_group('base.group_system'))
        if not allowed:
            raise ApiError('Demand not found.', 404, 'not_found')
        try:
            html = _demand_html(demand)
            pdf = request.env['ir.actions.report'].sudo()._run_wkhtmltopdf([html])
        except Exception as error:
            raise ApiError('Failed to generate Demand PDF: %s' % error, 500, 'pdf_error')
        name = 'Demand_%s.pdf' % (demand.name or demand_id).replace('/', '_')
        return request.make_response(pdf, headers=[
            ('Content-Type', 'application/pdf'),
            ('Content-Length', len(pdf)),
            ('Content-Disposition', 'attachment; filename="%s"' % name),
        ])

    @api_route('/api/v1/orders/<int:order_id>/summary.pdf', methods=('GET',))
    def order_summary_pdf(self, employee, order_id, **kw):
        """The outlet-by-outlet summary, ready to be passed on to the distributor."""
        order = request.env['sale.order'].sudo().browse(order_id).exists()
        allowed = order and (order.ff_employee_id == employee
                             or order.ff_employee_id in employee._ff_subordinates())
        if not allowed:
            raise ApiError('Order not found.', 404, 'not_found')
        report = request.env.ref('ff_demand.action_report_ff_distributor_summary').sudo()
        pdf, _kind = report._render_qweb_pdf(report.report_name, res_ids=order.ids)
        name = 'Order Summary - %s.pdf' % (order.name or order.id)
        return request.make_response(pdf, headers=[
            ('Content-Type', 'application/pdf'),
            ('Content-Length', len(pdf)),
            ('Content-Disposition', 'attachment; filename="%s"' % name),
        ])

    @api_route('/api/v1/order-flow', methods=('GET',))
    def flow(self, employee, **kw):
        """The app asks once at login which document its orders become."""
        return ok({'flow': order_flow(request.env)})
