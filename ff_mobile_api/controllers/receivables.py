"""Money customers owe: open invoices with due and overdue, ageing, and a statement of account.

Only customers the employee can see (their Data Access) are included, in the
company currency, from posted accounting entries.
"""
from datetime import timedelta
import re
import html
from html import escape

from odoo import fields, http
from odoo.http import request

from odoo.addons.ff_base.tools import to_iso

from .clients import client_domain, to_int, visible_client
from .common import ApiError, api_route, ok, ref

BUCKETS = [('not_due', 'Not due'), ('1_30', '1–30 days'), ('31_60', '31–60 days'),
           ('61_90', '61–90 days'), ('90_plus', 'Over 90 days')]


def _bucket(days_overdue):
    if days_overdue <= 0:
        return 'not_due'
    if days_overdue <= 30:
        return '1_30'
    if days_overdue <= 60:
        return '31_60'
    if days_overdue <= 90:
        return '61_90'
    return '90_plus'


def _due(move):
    """The due date of the invoice, as it is on the invoice: it is set when the invoice is created or posted, from the
    contact's credit days or the default due days of the settings (ff_outlet_ledger)."""
    return move.invoice_date_due


def _sales_employee(move):
    """The field employee whose order the invoice is for, else the salesperson on the invoice."""
    orders = move.invoice_line_ids.sale_line_ids.order_id
    employee = orders.filtered('ff_employee_id')[:1].ff_employee_id if 'ff_employee_id' in orders._fields else None
    return (employee.name if employee else None) or move.invoice_user_id.name or None


def _check_accounting():
    if 'account.move' not in request.env:
        raise ApiError('Invoicing is not installed.', 404, 'not_found')


def _reach(employee, partner_id=None):
    """The branches of the move domain: the customers this person can see and, for a list that is not of one
    customer, anything billed on an order they or their team raised. Returns ``(branches, families)``."""
    env = request.env
    if partner_id:
        partners = visible_client(employee, to_int(partner_id))
    else:
        partners = env['res.partner'].sudo().search(client_domain(employee))
    families = partners.mapped('commercial_partner_id')
    mine = (employee | employee._ff_subordinates()).ids
    reach = [[('partner_id', 'child_of', families.ids)]] if families else []
    Order = env.get('sale.order')
    if not partner_id and Order is not None and 'ff_employee_id' in Order._fields:
        reach.append([('invoice_line_ids.sale_line_ids.order_id.ff_employee_id', 'in', mine)])
    return reach, families






def _soa_html(partner, company, start_date, end_date, opening, rows, closing, currency):
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
    cust_addr = ', '.join(filter(None, [partner.street, partner.street2, partner.city, partner.zip])) if partner else ''

    total_debit = sum(r['debit'] for r in rows)
    total_credit = sum(r['credit'] for r in rows)

    start_str = start_date.strftime('%d-%b-%Y') if start_date else ''
    end_str = end_date.strftime('%d-%b-%Y') if end_date else ''

    lines_html = []
    # Opening balance
    lines_html.append("""
        <tr style="background:#f8fafc;font-weight:bold;">
            <td style="border:1px solid #cbd5e1;padding:6px 8px;text-align:center;">%s</td>
            <td style="border:1px solid #cbd5e1;padding:6px 8px;" colspan="2">Opening Balance</td>
            <td style="border:1px solid #cbd5e1;padding:6px 8px;text-align:center;">-</td>
            <td style="border:1px solid #cbd5e1;padding:6px 8px;text-align:right;">-</td>
            <td style="border:1px solid #cbd5e1;padding:6px 8px;text-align:right;">-</td>
            <td style="border:1px solid #cbd5e1;padding:6px 8px;text-align:right;">%s %.2f</td>
        </tr>
    """ % (start_str, currency, opening))

    for r in rows:
        d_str = r['date'][:10] if r.get('date') else ''
        try:
            d_obj = fields.Date.to_date(d_str)
            d_fmt = d_obj.strftime('%d-%b-%Y') if d_obj else d_str
        except Exception:
            d_fmt = d_str

        due_str = r['due_date'][:10] if r.get('due_date') else '-'
        try:
            due_obj = fields.Date.to_date(due_str)
            due_fmt = due_obj.strftime('%d-%b-%Y') if due_obj else due_str
        except Exception:
            due_fmt = due_str

        num_str = escape(r['number'] or '')
        ref_str = escape(r.get('reference') or '')
        particulars = num_str
        if ref_str and ref_str != num_str:
            particulars += '<br/><span style="font-size:8pt;color:#64748b;">Ref: %s</span>' % ref_str

        kind_str = escape(r.get('kind') or '')
        debit_str = ('%.2f' % r['debit']) if r.get('debit') else '-'
        credit_str = ('%.2f' % r['credit']) if r.get('credit') else '-'

        lines_html.append("""
            <tr>
                <td style="border:1px solid #cbd5e1;padding:6px 8px;text-align:center;">%s</td>
                <td style="border:1px solid #cbd5e1;padding:6px 8px;"><b>%s</b></td>
                <td style="border:1px solid #cbd5e1;padding:6px 8px;text-align:center;"><span style="font-size:8pt;background:#e2e8f0;padding:2px 6px;border-radius:4px;">%s</span></td>
                <td style="border:1px solid #cbd5e1;padding:6px 8px;text-align:center;">%s</td>
                <td style="border:1px solid #cbd5e1;padding:6px 8px;text-align:right;color:#0f172a;">%s</td>
                <td style="border:1px solid #cbd5e1;padding:6px 8px;text-align:right;color:#16a34a;">%s</td>
                <td style="border:1px solid #cbd5e1;padding:6px 8px;text-align:right;font-weight:bold;">%s %.2f</td>
            </tr>
        """ % (d_fmt, particulars, kind_str, due_fmt, debit_str, credit_str, currency, r['balance']))

    lines_html.append("""
        <tr style="background:#f1f5f9;font-weight:bold;">
            <td colspan="4" style="border:1px solid #cbd5e1;padding:8px;text-align:right;">TOTALS / CLOSING BALANCE</td>
            <td style="border:1px solid #cbd5e1;padding:8px;text-align:right;">%s %.2f</td>
            <td style="border:1px solid #cbd5e1;padding:8px;text-align:right;color:#16a34a;">%s %.2f</td>
            <td style="border:1px solid #cbd5e1;padding:8px;text-align:right;color:#1B3A7A;font-size:10.5pt;">%s %.2f</td>
        </tr>
    """ % (currency, total_debit, currency, total_credit, currency, closing))

    now_str = fields.Datetime.now().strftime('%d-%b-%Y %I:%M %p')

    html_doc = """<!DOCTYPE html>
<html>
<head>
    <meta charset="utf-8"/>
    <title>Statement of Account - %(cust_name)s</title>
    <style>
        @page { size: A4 portrait; margin: 10mm; }
        body { font-family: Arial, Helvetica, sans-serif; color: #1e293b; font-size: 9pt; line-height: 1.35; margin: 0; padding: 20px 24px; }
        .page-wrap { width: 100%%; box-sizing: border-box; }
        .header-table { width: 100%%; border-collapse: collapse; margin-bottom: 14px; }
        .cards-table { width: 100%%; border-collapse: collapse; margin-bottom: 14px; }
        .party-card { border: 1px solid #cbd5e1; border-radius: 6px; vertical-align: top; width: 100%%; background: #fff; }
        .party-header { background: #f1f5f9; padding: 6px 10px; font-weight: bold; font-size: 8.5pt; border-bottom: 1px solid #cbd5e1; color: #334155; }
        .party-body { padding: 8px 10px; }
        .summary-table { width: 100%%; border-collapse: collapse; margin-bottom: 14px; }
        .summary-table td { padding: 8px 12px; border: 1px solid #cbd5e1; text-align: center; }
        .summary-val { font-size: 11pt; font-weight: bold; margin-top: 4px; }
        .items-table { width: 100%%; border-collapse: collapse; margin-bottom: 14px; }
        .items-table th { background: #1B3A7A; color: #ffffff; border: 1px solid #1B3A7A; padding: 6px 8px; font-size: 8.5pt; font-weight: bold; }
        .footer { clear: both; padding-top: 14px; border-top: 1px dashed #cbd5e1; font-size: 8pt; color: #64748b; text-align: center; }
    </style>
</head>
<body>
<div class="page-wrap">
    <table class="header-table">
        <tr>
            <td style="vertical-align:top;width:55%%;">
                %(logo_html)s
                <div style="color:#64748b;font-size:8.5pt;margin-top:4px;">
                    %(company_addr)s<br/>
                    %(company_phone)s%(company_gst)s
                </div>
            </td>
            <td style="vertical-align:top;text-align:right;width:45%%;">
                <h2 style="margin:0;color:#1B3A7A;font-size:16pt;font-weight:900;letter-spacing:0.5px;">STATEMENT OF ACCOUNT</h2>
                <div style="margin-top:6px;font-size:9pt;color:#334155;">
                    <b>Period:</b> %(start_str)s to %(end_str)s<br/>
                    <b>Date Generated:</b> %(now_str)s
                </div>
            </td>
        </tr>
    </table>

    <table class="cards-table">
        <tr>
            <td style="width:100%%;vertical-align:top;">
                <div class="party-card">
                    <div class="party-header">CUSTOMER DETAILS</div>
                    <div class="party-body">
                        <b style="font-size:10.5pt;color:#0f172a;">%(cust_name)s</b><br/>
                        %(cust_addr)s<br/>
                        %(cust_phone)s%(cust_gst)s
                    </div>
                </div>
            </td>
        </tr>
    </table>

    <table class="summary-table">
        <tr style="background:#f8fafc;">
            <td style="width:25%%;">
                <div style="font-size:8pt;color:#64748b;text-transform:uppercase;font-weight:bold;">Opening Balance</div>
                <div class="summary-val" style="color:#334155;">%(currency)s %(opening_fmt)s</div>
            </td>
            <td style="width:25%%;">
                <div style="font-size:8pt;color:#64748b;text-transform:uppercase;font-weight:bold;">Total Billed (Dr)</div>
                <div class="summary-val" style="color:#0f172a;">%(currency)s %(total_debit_fmt)s</div>
            </td>
            <td style="width:25%%;">
                <div style="font-size:8pt;color:#64748b;text-transform:uppercase;font-weight:bold;">Total Paid (Cr)</div>
                <div class="summary-val" style="color:#16a34a;">%(currency)s %(total_credit_fmt)s</div>
            </td>
            <td style="width:25%%;background:#eff6ff;">
                <div style="font-size:8pt;color:#1e40af;text-transform:uppercase;font-weight:bold;">Closing Balance</div>
                <div class="summary-val" style="color:#1B3A7A;">%(currency)s %(closing_fmt)s</div>
            </td>
        </tr>
    </table>

    <table class="items-table">
        <thead>
            <tr>
                <th style="width:11%%;text-align:center;">Date</th>
                <th style="width:28%%;text-align:left;">Particulars / Ref</th>
                <th style="width:13%%;text-align:center;">Type</th>
                <th style="width:11%%;text-align:center;">Due Date</th>
                <th style="width:12%%;text-align:right;">Debit (Dr)</th>
                <th style="width:12%%;text-align:right;">Credit (Cr)</th>
                <th style="width:13%%;text-align:right;">Balance</th>
            </tr>
        </thead>
        <tbody>
            %(lines_html)s
        </tbody>
    </table>

    <div class="footer">
        This is a computer generated statement and requires no physical signature.<br/>
        %(company_name)s &bull; Generated on %(now_str)s
    </div>
</div>
</body>
</html>
""" % {
        'cust_name': escape(partner.name or ''),
        'cust_addr': escape(cust_addr),
        'cust_phone': ('Phone: %s<br/>' % escape(partner.phone)) if partner.phone else '',
        'cust_gst': ('GSTIN: %s' % escape(partner.vat)) if partner.vat else '',
        'logo_html': logo_html,
        'company_name': escape(company.name or ''),
        'company_addr': escape(company_addr),
        'company_phone': ('Phone: %s ' % escape(company.phone)) if company.phone else '',
        'company_gst': ('| GSTIN: %s' % escape(company.vat)) if company.vat else '',
        'start_str': start_str,
        'end_str': end_str,
        'now_str': now_str,
        'currency': currency,
        'opening_fmt': '%.2f' % opening,
        'total_debit_fmt': '%.2f' % total_debit,
        'total_credit_fmt': '%.2f' % total_credit,
        'closing_fmt': '%.2f' % closing,
        'lines_html': chr(10).join(lines_html),
    }
    return html_doc

def _invoice_html(move):
    company = move.company_id
    currency = move.currency_id.symbol or move.currency_id.name or '₹'
    customer = move.partner_id

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

    date_str = move.invoice_date.strftime('%d-%b-%Y') if move.invoice_date else ''
    due_str = move.invoice_date_due.strftime('%d-%b-%Y') if move.invoice_date_due else ''
    doc_title = 'CREDIT NOTE' if move.move_type == 'out_refund' else ('DEBIT NOTE' if move.move_type == 'in_refund' else 'TAX INVOICE')

    lines_html = []
    idx = 1
    for l in move.invoice_line_ids:
        if l.display_type:
            continue
        prod_name = escape(l.product_id.display_name or l.name or '')
        qty = ('%.2f' % l.quantity).rstrip('0').rstrip('.')
        uom = escape(l.product_uom_id.name or 'Pcs')
        rate = '%.2f' % (l.price_unit or 0.0)
        disc = (('%.2f' % l.discount).rstrip('0').rstrip('.') + '%') if (l.discount or 0) > 0 else '-'
        taxes = ', '.join(t.name for t in l.tax_ids) if l.tax_ids else '-'
        subtotal = '%.2f' % (l.price_subtotal or 0.0)

        lines_html.append("""
            <tr>
                <td style="border:1px solid #cbd5e1;padding:6px 8px;text-align:center;">%d</td>
                <td style="border:1px solid #cbd5e1;padding:6px 8px;"><b>%s</b></td>
                <td style="border:1px solid #cbd5e1;padding:6px 8px;text-align:right;">%s %s</td>
                <td style="border:1px solid #cbd5e1;padding:6px 8px;text-align:right;">%s %s</td>
                <td style="border:1px solid #cbd5e1;padding:6px 8px;text-align:center;">%s</td>
                <td style="border:1px solid #cbd5e1;padding:6px 8px;text-align:center;">%s</td>
                <td style="border:1px solid #cbd5e1;padding:6px 8px;text-align:right;font-weight:bold;">%s %s</td>
            </tr>
        """ % (idx, prod_name, qty, uom, currency, rate, disc, taxes, currency, subtotal))
        idx += 1

    html_doc = """<!DOCTYPE html>
<html>
<head>
    <meta charset="utf-8"/>
    <title>%(doc_title)s - %(doc_name)s</title>
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
                <div style="font-size:16pt;font-weight:900;color:#1B3A7A;letter-spacing:0.5px;">%(doc_title)s</div>
                <div style="font-size:12pt;font-weight:bold;color:#0f172a;margin-top:2px;">%(doc_name)s</div>
                <div style="font-size:8.5pt;color:#475569;margin-top:6px;">
                    <b>Date:</b> %(date_str)s<br/>
                    %(due_row)s
                    %(ref_row)s
                </div>
            </td>
        </tr>
    </table>

    <table class="cards-table">
        <tr>
            <td class="party-card">
                <div class="party-header">BILLED TO / CUSTOMER</div>
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
                <th>Description</th>
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
    %(narration_html)s

    <div class="footer">
        Generated by Field Force &bull; Official Document &bull; %(doc_name)s
    </div>
</div>
</body>
</html>""" % {
        'doc_title': escape(doc_title),
        'doc_name': escape(move.name or ''),
        'logo_html': logo_html,
        'company_addr': escape(company_addr),
        'company_phone': ('Phone: ' + escape(company.phone) + '<br/>') if company.phone else '',
        'company_vat': ('GSTIN: ' + escape(company.vat) + '<br/>') if getattr(company, 'vat', False) else '',
        'date_str': escape(date_str),
        'due_row': ('<b>Due Date:</b> ' + escape(due_str) + '<br/>') if due_str else '',
        'ref_row': ('<b>Reference:</b> ' + escape(move.ref) + '<br/>') if getattr(move, 'ref', False) else '',
        'cust_name': escape(customer.name or '-') if customer else '-',
        'cust_addr': escape(cust_addr),
        'cust_contact': ('Phone: ' + escape(customer.phone or getattr(customer, 'mobile', '') or '') + '<br/>') if (customer and (customer.phone or getattr(customer, 'mobile', ''))) else '',
        'cust_vat': ('GSTIN: ' + escape(customer.vat)) if (customer and getattr(customer, 'vat', False)) else '',
        'rows_html': ''.join(lines_html),
        'currency': escape(currency),
        'amount_untaxed': '%.2f' % (move.amount_untaxed or 0.0),
        'amount_tax': '%.2f' % (move.amount_tax or 0.0),
        'amount_total': '%.2f' % (move.amount_total or 0.0),
        'narration_html': ('<div style="margin-top:10px;padding:8px;background:#f8fafc;border:1px solid #cbd5e1;border-radius:4px;">' + escape(move.narration) + '</div>') if getattr(move, 'narration', False) else '',
    }
    return html_doc


class FieldForceReceivablesApi(http.Controller):

    @api_route('/api/v1/receivables', methods=('GET',))
    def receivables(self, employee, filter='open', q=None, partner_id=None, limit=None, kind=None, **kw):
        """Open invoices. filter: open (all unpaid), overdue, due_soon (next 7 days)."""
        _check_accounting()
        env = request.env
        today = employee._ff_today()
        company = employee.company_id
        if partner_id:
            partners = visible_client(employee, to_int(partner_id))
        else:
            domain = client_domain(employee)
            if q:
                domain = domain + ['|', ('name', 'ilike', q), ('ff_client_code', 'ilike', q)]
            partners = env['res.partner'].sudo().search(domain)
        families = partners.mapped('commercial_partner_id')
        move_domain = [
            ('move_type', 'in', ('out_invoice', 'out_refund')),
            ('state', '=', 'posted'), ('payment_state', 'in', ('not_paid', 'partial')),
            ('company_id', '=', company.id),
        ]
        # Whose money to chase: the customers this person can see, and anything
        # billed on an order they raised. The second matters on the demand flow,
        # where the invoice goes to a distributor the outlet's rep may not have
        # on their own list at all - but it is still their order to collect.
        mine = (employee | employee._ff_subordinates()).ids
        reach = [[('partner_id', 'child_of', families.ids)]] if families else []
        Order = env.get('sale.order')
        if not partner_id and Order is not None and 'ff_employee_id' in Order._fields:
            reach.append([('invoice_line_ids.sale_line_ids.order_id.ff_employee_id', 'in', mine)])
        # Every open item as one list: the posted invoices, and the invoices the outlets owe through the demand flow.
        items = []
        if reach:
            move_domain += ['|'] * (len(reach) - 1) + [term for branch in reach for term in branch]
            # Outlets or distributors only, when one of the two buttons is chosen.
            if kind in ('outlet', 'distributor'):
                move_domain.append(('partner_id.commercial_partner_id.ff_category_type', '=', kind))
            for move in env['account.move'].sudo().search(move_domain, limit=5000):
                items.append({
                    'id': move.id, 'source': 'move', 'number': move.name,
                    'who': move.partner_id.commercial_partner_id, 'date': move.invoice_date,
                    'due': _due(move), 'amount': move.amount_total_signed, 'residual': move.amount_residual_signed,
                    'refund': move.move_type == 'out_refund', 'salesperson': _sales_employee(move)})
        if 'ff.outlet.invoice' in env and kind in (None, '', 'outlet'):
            outlet_domain = [('state', 'in', ('open', 'partial')), ('company_id', '=', company.id)]
            if partner_id:
                outlet_domain.append(('partner_id', 'child_of', families.ids))
            else:
                outlet_domain += ['|', ('partner_id', 'child_of', families.ids), ('employee_id', 'in', mine)]
            for invoice in env['ff.outlet.invoice'].sudo().search(outlet_domain, limit=5000):
                items.append({
                    'id': invoice.id, 'source': 'outlet', 'number': invoice.name,
                    'who': invoice.partner_id.commercial_partner_id, 'date': invoice.date,
                    'due': invoice.due_date, 'amount': invoice.amount_total, 'residual': invoice.amount_pending,
                    'refund': False, 'salesperson': invoice.employee_id.name or None})
        # The due date is each invoice's own, so overdue and due-soon are filtered here, not in the query.
        if filter == 'overdue':
            items = [i for i in items if i['due'] and i['due'] < today]
        elif filter == 'due_soon':
            items = [i for i in items if i['due'] and today <= i['due'] <= today + timedelta(days=7)]
        items.sort(key=lambda i: (i['due'] or today, i['id']))
        shown = min(to_int(limit) or 200, 500)
        ageing = {key: 0.0 for key, _label in BUCKETS}
        rows, total, overdue = [], 0.0, 0.0
        customers = {}
        for item in items:
            residual = item['residual']
            due = item['due']
            late_days = (today - due).days if due else 0
            bucket = _bucket(late_days)
            ageing[bucket] += residual
            total += residual
            if late_days > 0 and residual > 0:
                overdue += residual
            who = item['who']
            row = customers.setdefault(who.id, {
                'customer': ref(who), 'total': 0.0, 'overdue': 0.0, 'count': 0, 'days_overdue': 0, 'bucket': 'not_due'})
            row['total'] += residual
            row['count'] += 1
            if late_days > 0 and residual > 0:
                row['overdue'] += residual
            if late_days > row['days_overdue']:
                row['days_overdue'], row['bucket'] = late_days, bucket
            if len(rows) >= shown:
                continue
            rows.append({
                'id': item['id'],
                'source': item['source'],
                'number': item['number'],
                'customer': ref(who),
                'date': to_iso(item['date']),
                'due_date': to_iso(due),
                'amount': round(item['amount'], 2),
                'residual': round(residual, 2),
                'days_overdue': max(late_days, 0),
                'bucket': bucket,
                'is_refund': item['refund'],
                'salesperson': item['salesperson'],
            })
        # Nothing owing and nothing to show is one thing; an invoice sitting in
        # draft is another, and it is the usual reason somebody says their
        # receivables are missing. Count them so the app can say so.
        drafts = 0
        if not rows and reach:
            draft_domain = [
                ('move_type', 'in', ('out_invoice', 'out_refund')),
                ('state', '=', 'draft'), ('company_id', '=', company.id),
            ] + ['|'] * (len(reach) - 1) + [term for branch in reach for term in branch]
            if kind in ('outlet', 'distributor'):
                draft_domain.append(('partner_id.commercial_partner_id.ff_category_type', '=', kind))
            drafts = env['account.move'].sudo().search_count(draft_domain)
        return ok({
            'currency': company.currency_id.name,
            'filter': filter,
            'total': round(total, 2),
            'overdue': round(overdue, 2),
            'count': len(items),
            'draft_count': drafts,
            'ageing': [{'key': key, 'label': label, 'amount': round(ageing[key], 2)} for key, label in BUCKETS],
            'invoices': rows,
            # Contact by contact, the biggest balance first.
            'customers': sorted(
                ({**c, 'total': round(c['total'], 2), 'overdue': round(c['overdue'], 2)} for c in customers.values()),
                key=lambda c: -c['total']),
        })

    @api_route('/api/v1/receivables/invoice/<int:move_id>', methods=('GET',))
    def invoice(self, employee, move_id, **kw):
        """One open invoice: its items, payment terms, taxes and what has been paid."""
        _check_accounting()
        env = request.env
        reach, _families = _reach(employee)
        if not reach:
            raise ApiError('Invoice not found.', 404, 'not_found')
        domain = [('id', '=', move_id), ('move_type', 'in', ('out_invoice', 'out_refund')),
                  ('state', '=', 'posted')] + ['|'] * (len(reach) - 1) + [t for b in reach for t in b]
        move = env['account.move'].sudo().search(domain, limit=1)
        if not move:
            raise ApiError('Invoice not found.', 404, 'not_found')
        today = employee._ff_today()
        due = _due(move)
        late = (today - due).days if due else 0
        lines = []
        for line in move.invoice_line_ids.filtered(lambda l: l.display_type == 'product'):
            lines.append({
                'product': line.product_id.display_name if line.product_id else (line.name or ''),
                'name': line.name or '',
                'qty': line.quantity, 'uom': line.product_uom_id.name or None,
                'price_unit': line.price_unit, 'discount': line.discount,
                'taxes': [t.name for t in line.tax_ids],
                'subtotal': line.price_subtotal, 'total': line.price_total,
            })
        widget = move.invoice_payments_widget or {}
        payments = [{'date': str(item.get('date') or '') or None, 'amount': item.get('amount'),
                     'name': item.get('ref') or item.get('name') or None}
                    for item in (widget.get('content', []) if isinstance(widget, dict) else [])]
        order = move.invoice_line_ids.sale_line_ids.order_id[:1]
        return ok({
            'id': move.id, 'number': move.name, 'is_refund': move.move_type == 'out_refund',
            'customer': ref(move.partner_id.commercial_partner_id),
            'billed_to': ref(move.partner_id),
            'date': to_iso(move.invoice_date), 'due_date': to_iso(due),
            'days_overdue': max(late, 0), 'bucket': _bucket(late),
            # The terms of the invoice, or - when the due date comes from the contact's credit days - those days.
            'payment_terms': move.invoice_payment_term_id.name or (
                '%s days credit' % (due - move.invoice_date).days if due and move.invoice_date else None),
            'payment_state': move.payment_state, 'reference': move.ref or None,
            'order': order.name or None,
            'salesperson': _sales_employee(move),
            'currency': move.currency_id.name,
            'untaxed': move.amount_untaxed_signed, 'tax': move.amount_tax_signed,
            'total': move.amount_total_signed, 'paid': round(move.amount_total_signed - move.amount_residual_signed, 2),
            'residual': move.amount_residual_signed,
            'lines': lines, 'payments': payments, 'narration': None,
        })

    @api_route('/api/v1/receivables/invoice/<int:move_id>/pdf', methods=('GET',))
    @api_route('/api/v1/invoices/<int:move_id>/pdf', methods=('GET',))
    def invoice_pdf(self, employee, move_id, **kw):
        """Downloads the PDF for an invoice, credit note or debit note (account.move)."""
        _check_accounting()
        env = request.env
        move = env['account.move'].sudo().browse(move_id).exists()
        if not move:
            raise ApiError('Invoice not found.', 404, 'not_found')
        pdf = None
        try:
            pdf, _kind = env['ir.actions.report'].sudo()._render_qweb_pdf('account.account_invoices', move.ids)
        except Exception:
            pdf = None

        if not pdf:
            try:
                html = _invoice_html(move)
                pdf = env['ir.actions.report'].sudo()._run_wkhtmltopdf([html])
            except Exception as error:
                raise ApiError('Failed to generate PDF: %s' % error, 500, 'pdf_error')

        prefix = 'Credit_Note' if move.move_type == 'out_refund' else ('Debit_Note' if move.move_type == 'in_refund' else 'Invoice')
        name = '%s_%s.pdf' % (prefix, (move.name or str(move_id)).replace('/', '_'))
        return request.make_response(pdf, headers=[
            ('Content-Type', 'application/pdf'),
            ('Content-Length', len(pdf)),
            ('Content-Disposition', 'attachment; filename="%s"' % name),
        ])

    @api_route('/api/v1/receivables/outlet-invoice/<int:invoice_id>', methods=('GET',))
    def outlet_invoice(self, employee, invoice_id, **kw):
        """One invoice an outlet owes through the demand flow: dates, credit days and what has been collected."""
        env = request.env
        mine = (employee | employee._ff_subordinates()).ids
        invoice = env['ff.outlet.invoice'].sudo().browse(invoice_id).exists()
        if not invoice or (invoice.employee_id.id not in mine and not env['res.partner'].sudo().search_count(
                client_domain(employee) + [('id', '=', invoice.partner_id.id)])):
            raise ApiError('Invoice not found.', 404, 'not_found')
        today = employee._ff_today()
        due = invoice.due_date
        late = (today - due).days if due else 0
        days = (due - invoice.date).days if due and invoice.date else None
        payments = [{'date': to_iso(line.payment_id.date) if 'date' in line.payment_id._fields else None,
                     'amount': line.amount, 'name': line.payment_id.display_name}
                    for line in invoice.payment_line_ids.filtered(lambda l: l.payment_id.state != 'rejected')]
        demand = invoice.demand_id
        lines = [{
            'product': l.product_id.display_name, 'name': l.product_id.display_name,
            'qty': l.quantity, 'uom': l.uom_id.name or None, 'price_unit': l.price_unit, 'discount': 0.0,
            'taxes': [t.name for t in l.tax_ids], 'subtotal': l.subtotal, 'total': l.price_total,
        } for l in demand.line_ids.filtered(lambda l: not getattr(l, 'is_foc', False))] if demand else []
        return ok({
            'id': invoice.id, 'number': invoice.name, 'is_refund': False,
            'customer': ref(invoice.partner_id.commercial_partner_id), 'billed_to': ref(invoice.partner_id),
            'date': to_iso(invoice.date), 'due_date': to_iso(due),
            'days_overdue': max(late, 0), 'bucket': _bucket(late),
            'payment_terms': '%s days credit' % days if days is not None else None,
            'payment_state': invoice.state, 'reference': None,
            'order': demand.name if demand else None,
            'salesperson': invoice.employee_id.name or None,
            'currency': invoice.currency_id.name,
            'untaxed': sum(demand.line_ids.mapped('subtotal')) if demand else invoice.amount_total,
            'tax': sum(demand.line_ids.mapped('price_tax')) if demand else 0.0,
            'total': invoice.amount_total, 'paid': round(invoice.amount_total - invoice.amount_pending, 2),
            'residual': invoice.amount_pending,
            'lines': lines, 'payments': payments, 'narration': None,
        })

    @api_route('/api/v1/clients/<int:partner_id>/soa', methods=('GET',))
    def statement(self, employee, partner_id, start=None, end=None, **kw):
        """Statement of account: opening balance, every posted receivable entry in the period, closing balance."""
        _check_accounting()
        partner = visible_client(employee, partner_id).commercial_partner_id
        today = employee._ff_today()
        try:
            end_date = fields.Date.to_date(end) if end else today
            start_date = fields.Date.to_date(start) if start else end_date.replace(day=1) - timedelta(days=90)
        except ValueError:
            raise ApiError('Dates must be YYYY-MM-DD.')
        company = employee.company_id
        Line = request.env['account.move.line'].sudo()
        base = [('partner_id', 'child_of', partner.id), ('account_id.account_type', '=', 'asset_receivable'),
                ('parent_state', '=', 'posted'), ('company_id', '=', company.id)]
        opening = sum(Line.search(base + [('date', '<', start_date)]).mapped('balance'))
        running = opening
        rows = []
        for line in Line.search(base + [('date', '>=', start_date), ('date', '<=', end_date)], order='date asc, id asc'):
            running += line.balance
            move = line.move_id
            kind = {'out_invoice': 'Invoice', 'out_refund': 'Credit note'}.get(
                move.move_type, 'Payment' if line.credit else 'Adjustment')
            rows.append({
                'date': to_iso(line.date),
                'number': move.name,
                'kind': kind,
                'reference': move.ref or line.name or None,
                'due_date': to_iso(line.date_maturity),
                'debit': round(line.debit, 2),
                'credit': round(line.credit, 2),
                'balance': round(running, 2),
            })
        return ok({
            'customer': ref(partner),
            'currency': company.currency_id.name,
            'start': start_date.isoformat(),
            'end': end_date.isoformat(),
            'opening': round(opening, 2),
            'closing': round(running, 2),
            'debit': round(sum(r['debit'] for r in rows), 2),
            'credit': round(sum(r['credit'] for r in rows), 2),
            'lines': rows,
        })

    @api_route('/api/v1/clients/<int:partner_id>/soa/pdf', methods=('GET',))
    def statement_pdf(self, employee, partner_id, start=None, end=None, **kw):
        """Statement of account PDF download."""
        _check_accounting()
        partner = visible_client(employee, partner_id).commercial_partner_id
        today = employee._ff_today()
        try:
            end_date = fields.Date.to_date(end) if end else today
            start_date = fields.Date.to_date(start) if start else end_date.replace(day=1) - timedelta(days=90)
        except ValueError:
            raise ApiError('Dates must be YYYY-MM-DD.')
        company = employee.company_id
        Line = request.env['account.move.line'].sudo()
        base = [('partner_id', 'child_of', partner.id), ('account_id.account_type', '=', 'asset_receivable'),
                ('parent_state', '=', 'posted'), ('company_id', '=', company.id)]
        opening = sum(Line.search(base + [('date', '<', start_date)]).mapped('balance'))
        running = opening
        rows = []
        for line in Line.search(base + [('date', '>=', start_date), ('date', '<=', end_date)], order='date asc, id asc'):
            running += line.balance
            move = line.move_id
            kind = {'out_invoice': 'Invoice', 'out_refund': 'Credit note'}.get(
                move.move_type, 'Payment' if line.credit else 'Adjustment')
            rows.append({
                'date': to_iso(line.date),
                'number': move.name,
                'kind': kind,
                'reference': move.ref or line.name or None,
                'due_date': to_iso(line.date_maturity),
                'debit': round(line.debit, 2),
                'credit': round(line.credit, 2),
                'balance': round(running, 2),
            })
        currency = company.currency_id.symbol or company.currency_id.name or '₹'
        html = _soa_html(partner, company, start_date, end_date, opening, rows, running, currency)
        try:
            pdf = request.env['ir.actions.report'].sudo()._run_wkhtmltopdf([html])
        except Exception as error:
            raise ApiError('Failed to generate Statement PDF: %s' % error, 500, 'pdf_error')

        name = 'SOA_%s_%s_%s.pdf' % (
            re.sub(r'[^a-zA-Z0-9_-]', '_', partner.name or str(partner_id)),
            start_date.strftime('%Y%m%d'),
            end_date.strftime('%Y%m%d')
        )
        return request.make_response(pdf, headers=[
            ('Content-Type', 'application/pdf'),
            ('Content-Length', len(pdf)),
            ('Content-Disposition', 'inline; filename="%s"' % name),
        ])
