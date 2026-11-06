"""Credit and debit notes a manager decides from the app."""
import html
from html import escape
from odoo import http
from odoo.http import request

from odoo.addons.ff_mobile_api.controllers.common import ApiError, api_route, note_rejection, ok




def _note_html(note):
    company = note.company_id
    currency = note.currency_id.symbol or note.currency_id.name or '₹'
    outlet = note.partner_id
    distributor = note.distributor_id
    employee = note.employee_id

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
    date_str = note.date.strftime('%d-%b-%Y %I:%M %p') if note.date else ''
    kind_title = 'CREDIT NOTE DEMAND' if note.kind == 'credit' else 'DEBIT NOTE DEMAND'
    state_label = dict(note._fields['state'].selection).get(note.state, note.state)

    lines_html = []
    idx = 1
    for l in note.line_ids:
        prod_name = escape(l.product_id.display_name or '')
        qty = ('%.2f' % l.quantity).rstrip('0').rstrip('.')
        rate = '%.2f' % (l.price_unit or 0.0)
        subtotal = '%.2f' % (l.subtotal or 0.0)

        lines_html.append("""
            <tr>
                <td style="border:1px solid #cbd5e1;padding:6px 8px;text-align:center;">%d</td>
                <td style="border:1px solid #cbd5e1;padding:6px 8px;"><b>%s</b></td>
                <td style="border:1px solid #cbd5e1;padding:6px 8px;text-align:right;">%s</td>
                <td style="border:1px solid #cbd5e1;padding:6px 8px;text-align:right;">%s %s</td>
                <td style="border:1px solid #cbd5e1;padding:6px 8px;text-align:right;font-weight:bold;">%s %s</td>
            </tr>
        """ % (idx, prod_name, qty, currency, rate, currency, subtotal))
        idx += 1

    html_doc = """<!DOCTYPE html>
<html>
<head>
    <meta charset="utf-8"/>
    <title>%(kind_title)s - %(note_name)s</title>
    <style>
        @page { size: A4; margin: 12mm; }
        body { font-family: Arial, Helvetica, sans-serif; color: #1e293b; font-size: 9.5pt; line-height: 1.35; margin: 0; padding: 0; }
        .header-table { width: 100%%; border-collapse: collapse; margin-bottom: 14px; }
        .cards-table { width: 100%%; border-collapse: separate; border-spacing: 10px 0; margin-left: -10px; margin-right: -10px; margin-bottom: 14px; }
        .party-card { border: 1px solid #cbd5e1; border-radius: 6px; vertical-align: top; width: 50%%; background: #fff; }
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
                <div style="font-size:16pt;font-weight:900;color:#1B3A7A;letter-spacing:0.5px;">%(kind_title)s</div>
                <div style="font-size:12pt;font-weight:bold;color:#0f172a;margin-top:2px;">%(note_name)s</div>
                <div style="margin-top:4px;"><span class="badge badge-status">%(state_label)s</span></div>
                <div style="font-size:8.5pt;color:#475569;margin-top:6px;">
                    <b>Date:</b> %(date_str)s<br/>
                    <b>Raised by:</b> %(employee_name)s<br/>
                    <b>Source:</b> %(source_label)s
                </div>
            </td>
        </tr>
    </table>

    <table class="cards-table">
        <tr>
            <td class="party-card">
                <div class="party-header">DISTRIBUTOR</div>
                <div class="party-body">
                    <div style="font-size:10pt;font-weight:bold;color:#0f172a;">%(dist_name)s</div>
                </div>
            </td>
            <td class="party-card">
                <div class="party-header">OUTLET</div>
                <div class="party-body">
                    <div style="font-size:10pt;font-weight:bold;color:#0f172a;">%(outlet_name)s</div>
                </div>
            </td>
        </tr>
    </table>

    <table class="items-table">
        <thead>
            <tr>
                <th style="width:28px;">#</th>
                <th>Product Description</th>
                <th style="width:70px;">Qty</th>
                <th style="width:80px;">Rate</th>
                <th style="width:90px;">Subtotal</th>
            </tr>
        </thead>
        <tbody>
            %(rows_html)s
        </tbody>
    </table>

    <table class="totals-table">
        <tr>
            <td style="background:#f8fafc;font-weight:bold;">Total Units</td>
            <td style="text-align:right;font-weight:bold;">%(qty_total)s</td>
        </tr>
        <tr style="font-size:10.5pt;background:#f1f5f9;">
            <td style="font-weight:900;color:#1B3A7A;">Total Value</td>
            <td style="text-align:right;font-weight:900;color:#1B3A7A;">%(currency)s %(amount_total)s</td>
        </tr>
    </table>

    <div style="clear:both;"></div>
    %(reason_html)s

    <div class="footer">
        Generated by Field Force &bull; Official Document &bull; %(note_name)s
    </div>
</body>
</html>""" % {
        'kind_title': escape(kind_title),
        'note_name': escape(note.name or ''),
        'logo_html': logo_html,
        'company_addr': escape(company_addr),
        'company_phone': ('Phone: ' + escape(company.phone) + '<br/>') if company.phone else '',
        'company_vat': ('GSTIN: ' + escape(company.vat) + '<br/>') if getattr(company, 'vat', False) else '',
        'state_label': escape(state_label),
        'date_str': escape(date_str),
        'employee_name': escape(employee.name or '-'),
        'source_label': escape(dict(note._fields['source'].selection).get(note.source, note.source or '-')),
        'dist_name': escape(distributor.name or '-') if distributor else '-',
        'outlet_name': escape(outlet.name or '-') if outlet else '-',
        'rows_html': ''.join(lines_html),
        'qty_total': ('%.2f' % (note.quantity_total or 0.0)).rstrip('0').rstrip('.'),
        'currency': escape(currency),
        'amount_total': '%.2f' % (note.amount or 0.0),
        'reason_html': ('<div style="margin-top:10px;padding:8px;background:#f8fafc;border:1px solid #cbd5e1;border-radius:4px;"><b>Reason:</b> ' + escape(note.reason) + '</div>') if note.reason else '',
    }
    return html_doc


class FieldForceNotesApi(http.Controller):

    @api_route('/api/v1/notes/to-approve', methods=('GET',), manager=True)
    def to_approve(self, employee, **kw):
        notes = request.env['ff.distributor.note'].sudo().search([
            ('employee_id', 'in', employee._ff_subordinates().ids), ('state', '=', 'pending')], limit=200)
        return ok([n.ff_approval_payload() for n in notes])

    @api_route('/api/v1/notes/<int:note_id>/<string:decision>', methods=('POST',), manager=True)
    def decide(self, employee, note_id, decision, **kw):
        if decision not in ('approve', 'reject'):
            raise ApiError('decision must be "approve" or "reject".')
        note = request.env['ff.distributor.note'].sudo().browse(note_id).exists()
        if not note:
            raise ApiError('Note not found.', 404, 'not_found')
        note.ff_decide_as(employee, decision == 'approve')
        note_rejection(note, decision == 'approve', employee)
        return ok(note.ff_approval_payload())


    @api_route('/api/v1/notes/<int:note_id>/pdf', methods=('GET',))
    def note_pdf(self, employee, note_id, **kw):
        """Downloads the PDF for a credit/debit note demand."""
        note = request.env['ff.distributor.note'].sudo().browse(note_id).exists()
        if not note:
            raise ApiError('Note not found.', 404, 'not_found')
        if note.move_id:
            try:
                pdf, _kind = request.env['ir.actions.report'].sudo()._render_qweb_pdf('account.account_invoices', note.move_id.ids)
                name = '%s_%s.pdf' % (('Credit_Note' if note.kind == 'credit' else 'Debit_Note'), (note.move_id.name or note.name or str(note.id)).replace('/', '_'))
                return request.make_response(pdf, headers=[
                    ('Content-Type', 'application/pdf'),
                    ('Content-Length', len(pdf)),
                    ('Content-Disposition', 'attachment; filename="%s"' % name),
                ])
            except Exception:
                pass

        try:
            html = _note_html(note)
            pdf = request.env['ir.actions.report'].sudo()._run_wkhtmltopdf([html])
        except Exception as error:
            raise ApiError('Failed to generate Note PDF: %s' % error, 500, 'pdf_error')

        name = '%s_%s.pdf' % (('Credit_Note' if note.kind == 'credit' else 'Debit_Note'), (note.name or str(note_id)).replace('/', '_'))
        return request.make_response(pdf, headers=[
            ('Content-Type', 'application/pdf'),
            ('Content-Length', len(pdf)),
            ('Content-Disposition', 'attachment; filename="%s"' % name),
        ])
