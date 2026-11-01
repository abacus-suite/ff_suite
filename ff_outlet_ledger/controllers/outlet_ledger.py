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

    @api_route('/api/v1/handovers/pending', methods=('GET',))
    def handover_pending(self, employee, **kw):
        """Outlet money still with the employee, grouped by the distributor it belongs to."""
        Handover = request.env['ff.distributor.handover']
        groups = []
        for distributor, payments in Handover.ff_pending(employee).items():
            groups.append({
                'distributor': {'id': distributor.id, 'name': distributor.name, 'phone': distributor.phone or None},
                'amount': sum(payments.mapped('amount_held')),
                'count': len(payments),
                'currency': payments[:1].currency_id.name,
                'oldest_date': min(payments.mapped('date')).isoformat(),
                'payments': [p.ff_app_payload() for p in payments],
            })
        return ok({'groups': groups, 'amount': sum(g['amount'] for g in groups)})

    @api_route('/api/v1/handovers', methods=('POST',))
    def handover_create(self, employee, **kw):
        handover = request.env['ff.distributor.handover'].ff_submit_from_app(employee, body())
        return ok(handover.ff_app_payload(lines=True), status=201)

    @api_route('/api/v1/handovers', methods=('GET',))
    def handover_list(self, employee, limit=None, **kw):
        records = request.env['ff.distributor.handover'].sudo().search(
            [('employee_id', '=', employee.id)], limit=min(to_int(limit) or 30, 100))
        return ok([h.ff_app_payload() for h in records])

    @api_route('/api/v1/team/collections', methods=('GET',), manager=True)
    def team_collections(self, employee, **kw):
        """Money the team has collected and still holds: for the office (from distributors) and for
        distributors (from outlets), by person, by distributor and by outlet."""
        env = request.env
        team = employee._ff_subordinates()
        people = {}

        def person(emp):
            return people.setdefault(emp.id, {
                'employee': ref(emp), 'office': 0.0, 'office_count': 0, 'oldest': None,
                'office_from': {}, 'dist_total': 0.0, 'dist_count': 0, 'distributors': {}})

        by_distributor, by_outlet = {}, {}
        currency = employee.company_id.currency_id.name

        for coll in env['ff.collection'].sudo().search([
                ('employee_id', 'in', team.ids), ('state', '=', 'collected'), ('mode_id.needs_deposit', '=', True)]):
            row = person(coll.employee_id)
            row['office'] += coll.amount
            row['office_count'] += 1
            when = coll.date.isoformat() if coll.date else None
            if when and (row['oldest'] is None or when < row['oldest']):
                row['oldest'] = when
            src = row['office_from'].setdefault(coll.partner_id.id, {'partner': ref(coll.partner_id), 'amount': 0.0, 'count': 0})
            src['amount'] += coll.amount
            src['count'] += 1
            item = by_distributor.setdefault(('office', coll.partner_id.id), {
                'distributor': ref(coll.partner_id), 'for': 'office', 'amount': 0.0, 'people': set()})
            item['amount'] += coll.amount
            item['people'].add(coll.employee_id.id)

        for pay in env['ff.outlet.payment'].sudo().search([
                ('employee_id', 'in', team.ids), ('amount_held', '>', 0.004), ('state', '!=', 'rejected')]):
            row = person(pay.employee_id)
            row['dist_total'] += pay.amount_held
            row['dist_count'] += 1
            dist = row['distributors'].setdefault(pay.distributor_id.id, {
                'distributor': ref(pay.distributor_id), 'amount': 0.0, 'outlets': {}})
            dist['amount'] += pay.amount_held
            outlet = dist['outlets'].setdefault(pay.partner_id.id, {
                'outlet': ref(pay.partner_id), 'amount': 0.0, 'count': 0, 'date': None})
            outlet['amount'] += pay.amount_held
            outlet['count'] += 1
            when = pay.date.isoformat() if pay.date else None
            if when and (outlet['date'] is None or when < outlet['date']):
                outlet['date'] = when
            item = by_distributor.setdefault(('dist', pay.distributor_id.id), {
                'distributor': ref(pay.distributor_id), 'for': 'distributor', 'amount': 0.0, 'people': set()})
            item['amount'] += pay.amount_held
            item['people'].add(pay.employee_id.id)
            out = by_outlet.setdefault(pay.partner_id.id, {
                'outlet': ref(pay.partner_id), 'distributor': ref(pay.distributor_id), 'amount': 0.0, 'people': set()})
            out['amount'] += pay.amount_held
            out['people'].add(pay.employee_id.id)

        members = []
        for row in people.values():
            members.append({
                'employee': row['employee'],
                'total': round(row['office'] + row['dist_total'], 2),
                'office': round(row['office'], 2), 'office_count': row['office_count'], 'oldest': row['oldest'],
                'office_from': sorted(({'partner': v['partner'], 'amount': round(v['amount'], 2), 'count': v['count']}
                                       for v in row['office_from'].values()), key=lambda v: -v['amount']),
                'distributor_total': round(row['dist_total'], 2), 'distributor_count': row['dist_count'],
                'distributors': sorted(({
                    'distributor': d['distributor'], 'amount': round(d['amount'], 2),
                    'outlets': sorted(({'outlet': o['outlet'], 'amount': round(o['amount'], 2), 'count': o['count'],
                                        'since': o['date']} for o in d['outlets'].values()), key=lambda o: -o['amount'])}
                    for d in row['distributors'].values()), key=lambda d: -d['amount']),
            })
        members.sort(key=lambda m: -m['total'])
        office = sum(m['office'] for m in members)
        dist = sum(m['distributor_total'] for m in members)
        return ok({
            'currency': currency,
            'totals': {'total': round(office + dist, 2), 'office': round(office, 2), 'distributors': round(dist, 2)},
            'members': members,
            'by_distributor': sorted(({'distributor': v['distributor'], 'for': v['for'], 'amount': round(v['amount'], 2),
                                       'people': len(v['people'])} for v in by_distributor.values()), key=lambda v: -v['amount']),
            'by_outlet': sorted(({'outlet': v['outlet'], 'distributor': v['distributor'], 'amount': round(v['amount'], 2),
                                  'people': len(v['people'])} for v in by_outlet.values()), key=lambda v: -v['amount']),
        })

    @api_route('/api/v1/handovers/to-confirm', methods=('GET',), manager=True)
    def handovers_to_confirm(self, employee, **kw):
        """Outlet money the team has handed to distributors, waiting for a manager to confirm."""
        records = request.env['ff.distributor.handover'].sudo().search([
            ('employee_id', 'in', employee._ff_subordinates().ids), ('state', '=', 'handed')])
        return ok([dict(h.ff_app_payload(lines=True), employee=ref(h.employee_id)) for h in records])

    @api_route('/api/v1/handovers/<int:handover_id>/<string:decision>', methods=('POST',), manager=True)
    def handover_decide(self, employee, handover_id, decision, **kw):
        if decision not in ('confirm', 'reject', 'approve'):
            raise ApiError('decision must be "confirm" or "reject".')
        record = request.env['ff.distributor.handover'].sudo().browse(handover_id).exists()
        if not record:
            raise ApiError('Handover not found.', 404, 'not_found')
        record.ff_decide_as(employee, decision != 'reject')
        return ok(record.ff_app_payload(lines=True))

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

    @api_route('/api/v1/clients/<int:partner_id>/ledger.pdf', methods=('GET',))
    def ledger_pdf(self, employee, partner_id, **kw):
        """The statement of account as one PDF: every invoice with its products, the payments, what is left."""
        partner = visible_client(employee, partner_id)
        report = request.env.ref('ff_outlet_ledger.action_report_ff_ledger_statement').sudo()
        pdf, _kind = report._render_qweb_pdf(report.report_name, res_ids=partner.ids)
        name = 'Statement - %s.pdf' % (partner.name or partner.id)
        return request.make_response(pdf, headers=[
            ('Content-Type', 'application/pdf'),
            ('Content-Length', len(pdf)),
            ('Content-Disposition', 'attachment; filename="%s"' % name),
        ])

