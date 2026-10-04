"""What the app needs to collect money properly.

Collecting asks one question the rest depends on: what is this money paying
for? From a distributor it pays the company's own invoices in Accounting. From
an outlet it pays that outlet's invoices from its distributor, which are kept
here. One endpoint answers for either, so the screen does not have to know
which it is dealing with.
"""
from odoo import http
from odoo.http import request

from odoo.addons.ff_mobile_api.controllers.clients import to_int, visible_client
from odoo.addons.ff_mobile_api.controllers.common import ApiError, api_route, body, ok, ref


class FieldForceOutletLedgerApi(http.Controller):

    @api_route('/api/v1/collection/open-invoices', methods=('GET',))
    def open_invoices(self, employee, partner_id=None, **kw):
        """The invoices a collection from this contact can be put against."""
        partner = visible_client(employee, to_int(partner_id))
        if partner.ff_is_distributor:
            kind, rows = 'company', self._company_invoices(partner)
        else:
            kind = 'outlet'
            invoices = request.env['ff.outlet.invoice'].sudo().search([
                ('partner_id', 'child_of', partner.commercial_partner_id.id),
                ('state', 'in', ('open', 'partial')),
            ], order='due_date asc, date asc, id asc')
            rows = [invoice.ff_app_payload() for invoice in invoices]
        return ok({
            'kind': kind,
            # Where the money ends up: the company for a distributor, the
            # outlet's own distributor for an outlet.
            'goes_to': 'company' if kind == 'company' else 'distributor',
            'distributor': ref(partner.ff_distributor_id) if kind == 'outlet' else None,
            'invoices': rows,
        })

    def _company_invoices(self, partner):
        if 'account.move' not in request.env:
            return []
        moves = request.env['account.move'].sudo().search([
            ('partner_id', 'child_of', partner.commercial_partner_id.id),
            ('move_type', '=', 'out_invoice'), ('state', '=', 'posted'),
            ('payment_state', 'in', ('not_paid', 'partial')),
        ], order='invoice_date_due asc, id asc')
        return [{
            'id': move.id,
            'number': move.name,
            'date': move.invoice_date.isoformat() if move.invoice_date else None,
            'due_date': move.invoice_date_due.isoformat() if move.invoice_date_due else None,
            'amount': move.amount_total,
            'pending': move.amount_residual,
            'currency': move.currency_id.name,
        } for move in moves]

    @api_route('/api/v1/outlet-invoices', methods=('POST',))
    def create_invoice(self, employee, **kw):
        """Enter an invoice a distributor has raised to an outlet."""
        data = body()
        visible_client(employee, to_int(data.get('partner_id')))
        invoice = request.env['ff.outlet.invoice'].ff_create_from_app(employee, data)
        return ok(invoice.ff_app_payload(), status=201)

    @api_route('/api/v1/outlet-invoices', methods=('GET',))
    def list_invoices(self, employee, partner_id=None, state=None, **kw):
        domain = [('employee_id', 'in', (employee | employee._ff_subordinates()).ids)]
        if partner_id:
            domain.append(('partner_id', 'child_of', visible_client(employee, to_int(partner_id)).id))
        if state == 'open':
            domain.append(('state', 'in', ('open', 'partial')))
        invoices = request.env['ff.outlet.invoice'].sudo().search(domain, limit=200)
        return ok([invoice.ff_app_payload() for invoice in invoices])
