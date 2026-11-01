"""Events: the cash and coupons table, completing the event, the distributor-wise report with its debit note,
the final report and their PDFs."""
import time as clock

from odoo import fields, http
from odoo.http import request

from odoo.addons.ff_app_reports.controllers.reports import LINK_SECONDS, _sign, _unsign
from odoo.addons.ff_mobile_api.controllers.common import ApiError, api_route, body, ok, ref

from .events import EPS, _code, _event_data, _mine, _report, event_mrp


def _first_day(event):
    days = event.day_ids.sorted('date')
    return days[0].date if days else event.date_start


def _share(total, weights):
    """Split ``total`` over the keys of ``weights`` in proportion to them, in whole bottles when ``total`` is a whole
    number (largest remainder, so the parts always add up to the total), else as plain fractions."""
    keys = [k for k, w in weights.items() if w > EPS]
    if not keys or total <= EPS:
        return {k: 0.0 for k in weights}
    weight_sum = sum(weights[k] for k in keys)
    exact = {k: total * weights[k] / weight_sum for k in keys}
    if abs(total - round(total)) > EPS or any(abs(weights[k] - round(weights[k])) > EPS for k in keys):
        return {k: exact.get(k, 0.0) for k in weights}
    parts = {k: int(exact[k]) for k in keys}
    left = int(round(total)) - sum(parts.values())
    for k in sorted(keys, key=lambda key: exact[key] - parts[key], reverse=True)[:left]:
        parts[k] += 1
    return {k: float(parts.get(k, 0)) for k in weights}


def _distributor_ledger(event):
    """What happened to each distributor's stock, day by day, from the figures the days were closed with.

    The staff count samples, damage and what stays at the event per flavour, not per distributor. So each day, for a
    flavour, the distributors' stock (what they had there at the start of the day plus what was added, less what was
    sent back to them, which is exact) is the pool, and samples, damage and sales are shared over the pools in
    proportion to their size. What is left is each distributor's closing stock, and it carries to the next day.
    Coupons of a day are shared in proportion to the bottles each distributor's stock sold that day.

    Returns ``{distributor id: {product id: {open, add, samples, damage, ret, closing, sold}}}`` and
    ``{distributor id: coupons}``.
    """
    days = event.day_ids.sorted('date')
    ledger = {}
    coupons = {}
    carry = {}  # (distributor, product) -> what that distributor's stock closed the day before at
    previous = None
    for day in days:
        since = previous.date if previous else None
        fresh = {}
        for stock in event.stock_ids:
            if stock.date <= day.date and (since is None or stock.date > since):
                key = (stock.distributor_id.id, stock.product_id.id)
                fresh[key] = fresh.get(key, 0.0) + stock.qty
        returned = {}
        for ret in day.return_ids:
            key = (ret.distributor_id.id, ret.product_id.id)
            returned[key] = returned.get(key, 0.0) + ret.qty
        stock_came_back = previous is not None and previous.closing_action == 'return'
        start = {} if (previous is None or stock_came_back) else dict(carry)
        closing_today = {}
        sold_by_distributor = {}
        for line in day.line_ids:
            pid = line.product_id.id
            who = {d for (d, p) in list(start) + list(fresh) + list(returned) if p == pid}
            pools, opening, added, raw = {}, {}, {}, {}
            for d in who:
                key = (d, pid)
                if previous is None or stock_came_back:
                    opening[d], added[d] = fresh.get(key, 0.0), 0.0
                else:
                    opening[d], added[d] = start.get(key, 0.0), fresh.get(key, 0.0)
                raw[d] = opening[d] + added[d] - returned.get(key, 0.0)
            # A distributor can be sent back more than it supplied (stock of another distributor): its figure is then
            # below zero. Those who supplied more than they got back cover that, in proportion to what they have, and
            # the samples, damage and sales are shared over what each still holds.
            shortfall = -sum(v for v in raw.values() if v < 0)
            surplus = sum(v for v in raw.values() if v > 0)
            moved = {}
            for d in who:
                if raw[d] > 0 and surplus > EPS:
                    gave = shortfall * raw[d] / surplus
                    pools[d] = raw[d] - gave
                    moved[d] = gave
                else:
                    pools[d] = 0.0
                    moved[d] = raw[d] if raw[d] < 0 else 0.0  # what it was given from others' stock, as a minus
            samples = _share(line.samples, pools)
            damage = _share(line.damage, pools)
            sold = _share(max(line.sold, 0.0), pools)
            for d in who:
                key = (d, pid)
                closing = max(pools[d] - samples[d] - damage[d] - sold[d], 0.0)
                closing_today[key] = closing
                row = ledger.setdefault(d, {}).setdefault(pid, {
                    'open': 0.0, 'add': 0.0, 'samples': 0.0, 'damage': 0.0, 'ret': 0.0, 'closing': 0.0, 'sold': 0.0,
                    'moved': 0.0})
                if days[0] == day:
                    row['open'] += opening[d]
                    row['add'] += added[d]
                else:
                    # Stock that came after the first day, or after the stock was sent back, is "added".
                    row['add'] += opening[d] - carry.get(key, 0.0) if not stock_came_back else opening[d]
                    row['add'] += added[d]
                row['samples'] += samples[d]
                row['damage'] += damage[d]
                row['moved'] += moved[d]
                row['ret'] += returned.get(key, 0.0)
                row['closing'] = closing
                row['sold'] += sold[d]
                sold_by_distributor[d] = sold_by_distributor.get(d, 0.0) + sold[d]
        for d, count in _share(float(day.coupons_used or 0), sold_by_distributor).items():
            coupons[d] = coupons.get(d, 0.0) + count
        carry = closing_today if day.closing_action != 'return' else {}
        previous = day
    return ledger, coupons


def _distributor_rows(event):
    """Per distributor and flavour: opening, added, returned and the net the event took (Opening + Added - Returned)."""
    first = _first_day(event)
    data = {}
    for stock in event.stock_ids:
        row = data.setdefault(stock.distributor_id.id, {'partner': stock.distributor_id, 'flavours': {}})
        f = row['flavours'].setdefault(stock.product_id.id, {
            'template': stock.product_id, 'open': 0.0, 'add': 0.0, 'ret': 0.0})
        if stock.date <= first:
            f['open'] += stock.qty
        else:
            f['add'] += stock.qty
    for day in event.day_ids:
        for ret in day.return_ids:
            row = data.setdefault(ret.distributor_id.id, {'partner': ret.distributor_id, 'flavours': {}})
            f = row['flavours'].setdefault(ret.product_id.id, {
                'template': ret.product_id, 'open': 0.0, 'add': 0.0, 'ret': 0.0})
            f['ret'] += ret.qty
    out = []
    company = event.employee_id.company_id.partner_id
    ledger, coupon_share = _distributor_ledger(event)
    value = int(event.offer_price or 0) if event.has_offer else 0
    for row in data.values():
        flavours = []
        mine = ledger.get(row['partner'].id, {})
        for f in sorted(row['flavours'].values(), key=lambda x: _code(x['template'])):
            f['net'] = f['open'] + f['add'] - f['ret']
            work = mine.get(f['template'].id, {})
            mrp = event_mrp(event, f['template'])
            sold = work.get('sold', 0.0)
            flavours.append({
                'product': ref(f['template']), 'code': _code(f['template']),
                'open': f['open'], 'add': f['add'], 'ret': f['ret'], 'net': f['net'],
                'moved': work.get('moved', 0.0),
                # What happened to the stock the event took from this distributor.
                'samples': work.get('samples', 0.0), 'damage': work.get('damage', 0.0),
                'closing': work.get('closing', 0.0), 'sold': sold,
                'mrp': mrp, 'sales': round(sold * mrp, 2)})
        totals = {k: sum(x[k] for x in flavours) for k in
                  ('open', 'add', 'ret', 'net', 'samples', 'damage', 'closing', 'sold', 'sales', 'moved')}
        # Positive net (it supplied more than it got back): a debit note. Negative (it got back more than it supplied):
        # an invoice for those bottles.
        totals['debit_qty'] = sum(max(x['net'], 0.0) for x in flavours)
        totals['invoice_qty'] = sum(max(-x['net'], 0.0) for x in flavours)
        coupons = int(round(coupon_share.get(row['partner'].id, 0.0)))
        totals.update({
            'coupons': coupons, 'coupon_amount': coupons * value,
            'net_sales': round(totals['sales'] - coupons * value, 2),
        })
        out.append({
            'distributor': ref(row['partner']), 'is_company': row['partner'] == company,
            'flavours': flavours, 'totals': totals,
        })
    out.sort(key=lambda r: (r['is_company'], r['distributor']['name']))
    return out


def _final(event, day=None):
    """The sales amount down to UPI received, for one day or the whole event."""
    rep = _report(event, day)
    value = int(event.offer_price or 0) if event.has_offer else 0
    rows = []
    for r in rep['rows']:
        mrp = r['mrp']
        template = request.env['product.template'].browse(r['product']['id'])
        mrp = event_mrp(event, template)
        rows.append(dict(r, mrp=mrp, sales=round(r['sold'] * mrp, 2)))
    days = event.day_ids.sorted('date')
    chosen = days.filtered(lambda d: d.date.isoformat() == day) if day else days
    coupons = sum(chosen.mapped('coupons_used'))
    cash = round(sum(chosen.mapped('cash_received')), 2)
    sales = round(sum(r['sales'] for r in rows), 2)
    coupon_amount = coupons * value
    net = round(sales - coupon_amount, 2)
    return {
        'event': _event_data(event), 'day': day,
        'days': [d.date.isoformat() for d in days],
        'rows': rows, 'totals': rep['totals'],
        'sales': sales, 'coupons': coupons, 'coupon_value': value, 'coupon_amount': coupon_amount,
        'net_sales': net, 'cash': cash, 'upi': round(net - cash, 2),
    }


def _day_table(event):
    out = []
    for d in event.day_ids.sorted('date'):
        f = _final(event, d.date.isoformat())
        out.append({
            'date': d.date.isoformat(), 'sold': f['totals']['sold'], 'sales': f['sales'],
            'coupons': f['coupons'], 'coupons_amount': f['coupon_amount'],
            'net_sales': f['net_sales'], 'cash': f['cash'], 'upi': f['upi'],
        })
    return out


def _html_table(title, subtitle, head, rows, foot=None, extra=''):
    def cell(v, tag='td'):
        return '<%s style="border:1px solid #999;padding:4px 8px;text-align:%s">%s</%s>' % (
            tag, 'left' if isinstance(v, str) and not v.replace('.', '').replace('-', '').isdigit() else 'right', v, tag)
    body_rows = ''.join('<tr>%s</tr>' % ''.join(cell(c) for c in r) for r in rows)
    foot_row = '<tr>%s</tr>' % ''.join(cell('<b>%s</b>' % c) for c in foot) if foot else ''
    return (
        '<html><head><meta charset="utf-8"/></head><body style="font-family:Arial;font-size:12px"><h2>%s</h2><div>%s</div><br/>'
        '<table style="border-collapse:collapse;width:100%%"><tr>%s</tr>%s%s</table>%s</body></html>' % (
            title, subtitle, ''.join(cell(h, 'th') for h in head), body_rows, foot_row, extra))


def _pdf(html):
    try:
        return request.env['ir.actions.report'].sudo()._run_wkhtmltopdf([html])
    except Exception as error:  # noqa: BLE001 - the server may have no PDF engine
        raise ApiError('A PDF cannot be made on this server (%s).' % error, 400, 'invalid')


class FieldForceEventReportsApi(http.Controller):

    @api_route('/api/v1/events/<int:event_id>/summary', methods=('GET',))
    def summary(self, employee, event_id, **kw):
        """Cash received and coupons used, day by day and till now."""
        event = _mine(employee, event_id)
        value = int(event.offer_price or 0) if event.has_offer else 0
        days = event.day_ids.sorted('date')
        return ok({
            'event': _event_data(event),
            'days': [{'date': d.date.isoformat(), 'cash': d.cash_received, 'coupons': d.coupons_used,
                      'is_final': d.is_final} for d in days],
            'cash_total': round(sum(days.mapped('cash_received')), 2),
            'coupons_total': sum(days.mapped('coupons_used')), 'coupon_value': value,
        })

    @api_route('/api/v1/events/<int:event_id>/complete', methods=('POST',))
    def complete(self, employee, event_id, **kw):
        event = _mine(employee, event_id)
        if event.state == 'done':
            return ok(_event_data(event, detail=True))
        if not event.day_ids.filtered('is_final'):
            raise ApiError('End of the Event is not done yet.', 400, 'invalid')
        last = event.day_ids.sorted('date')[-1]
        event.write({
            'state': 'done', 'date_end': last.date, 'completed_at': fields.Datetime.now(),
            'coupons_used': sum(event.day_ids.mapped('coupons_used')),
        })
        return ok(_event_data(event, detail=True))

    @api_route('/api/v1/events/<int:event_id>/distributors', methods=('GET',))
    def distributors(self, employee, event_id, **kw):
        event = _mine(employee, event_id)
        debits = {d.distributor_id.id: d for d in request.env['ff.event.debit'].sudo().search([
            ('event_id', '=', event.id)])}
        invoices = {i.distributor_id.id: i for i in request.env['ff.event.invoice'].sudo().search([
            ('event_id', '=', event.id)])}
        rows = _distributor_rows(event)
        for row in rows:
            debit = debits.get(row['distributor']['id'])
            row['debit_requested'] = bool(debit)
            row['debit_note'] = debit.note_id.name if debit and debit.note_id else None
            invoice = invoices.get(row['distributor']['id'])
            row['invoice_needed'] = row['totals']['invoice_qty'] > EPS and not row['is_company']
            row['invoice_requested'] = bool(invoice)
            row['invoice_number'] = invoice.move_name if invoice else None
        # The invoice summary: what was invoiced to which distributor, and what still has to be.
        summary = [{
            'distributor': row['distributor'], 'quantity': row['totals']['invoice_qty'],
            'amount': invoices[row['distributor']['id']].amount if row['distributor']['id'] in invoices else None,
            'number': row['invoice_number'], 'raised': row['invoice_requested'],
        } for row in rows if row['totals']['invoice_qty'] > EPS and not row['is_company']]
        return ok({'event': _event_data(event), 'distributors': rows, 'invoices': summary})

    @api_route('/api/v1/events/<int:event_id>/invoice', methods=('POST',))
    def invoice(self, employee, event_id, **kw):
        """Raise the invoice for a distributor that got back more than it supplied (a draft for the office)."""
        event = _mine(employee, event_id)
        env = request.env
        distributor_id = int(body().get('distributor_id') or 0)
        rows = [r for r in _distributor_rows(event) if r['distributor']['id'] == distributor_id]
        if not rows:
            raise ApiError('That distributor is not part of this event.', 404, 'not_found')
        row = rows[0]
        if row['is_company']:
            raise ApiError('An invoice is not raised to Kumbayah Foods.', 400, 'invalid')
        Invoice = env['ff.event.invoice'].sudo()
        existing = Invoice.search([('event_id', '=', event.id), ('distributor_id', '=', distributor_id)], limit=1)
        if existing:
            return ok({'raised': True, 'number': existing.move_name, 'amount': existing.amount})
        lines = [f for f in row['flavours'] if f['net'] < -EPS]
        if not lines:
            raise ApiError('Nothing to invoice: this distributor got back no more than it supplied.', 400, 'invalid')
        if 'account.move' not in env:
            raise ApiError('Invoicing is not set up on this server.', 400, 'invalid')
        partner = env['res.partner'].sudo().browse(distributor_id)
        company = event.employee_id.company_id
        invoice_lines, total, quantity = [], 0.0, 0.0
        for f in lines:
            product = env['product.template'].sudo().browse(f['product']['id']).product_variant_id
            if not product:
                continue
            price = product.ff_distributor_price(partner) if hasattr(product, 'ff_distributor_price') else product.lst_price
            qty = -f['net']
            invoice_lines.append((0, 0, {'product_id': product.id, 'quantity': qty, 'price_unit': price}))
            total += qty * price
            quantity += qty
        if not invoice_lines:
            raise ApiError('These flavours have no product to invoice.', 400, 'invalid')
        move = env['account.move'].sudo().with_company(company).create({
            'move_type': 'out_invoice', 'partner_id': partner.id, 'company_id': company.id,
            'invoice_origin': 'Event: %s' % event.name, 'ref': 'Event: %s' % event.name,
            'invoice_line_ids': invoice_lines,
        })
        Invoice.create({'event_id': event.id, 'distributor_id': distributor_id, 'move_ref': move.id,
                        'move_name': move.name or move.display_name, 'quantity': quantity,
                        'amount': round(move.amount_total or total, 2)})
        return ok({'raised': True, 'number': move.name or move.display_name, 'amount': round(move.amount_total or total, 2)})

    @api_route('/api/v1/events/<int:event_id>/debit-note', methods=('POST',))
    def debit_note(self, employee, event_id, **kw):
        """Ask a distributor for a debit note for what this event took from them (not for Kumbayah Foods)."""
        event = _mine(employee, event_id)
        distributor_id = int(body().get('distributor_id') or 0)
        rows = [r for r in _distributor_rows(event) if r['distributor']['id'] == distributor_id]
        if not rows:
            raise ApiError('That distributor is not part of this event.', 404, 'not_found')
        row = rows[0]
        if row['is_company']:
            raise ApiError('A debit note is not requested for Kumbayah Foods.', 400, 'invalid')
        Debit = request.env['ff.event.debit'].sudo()
        existing = Debit.search([('event_id', '=', event.id), ('distributor_id', '=', distributor_id)], limit=1)
        if existing:
            return ok({'requested': True, 'note': existing.note_id.name or None})
        lines = []
        for f in row['flavours']:
            template = request.env['product.template'].sudo().browse(f['product']['id'])
            product = template.product_variant_id
            if product and f['net'] > 0:
                lines.append({'product_id': product.id, 'qty': f['net']})
        note = request.env['ff.distributor.note'].ff_raise(
            event.employee_id, 'debit', lines, distributor=request.env['res.partner'].sudo().browse(distributor_id),
            reason='Event: %s' % event.name, source='other')
        Debit.create({'event_id': event.id, 'distributor_id': distributor_id, 'note_id': note.id or False,
                      'quantity': row['totals']['debit_qty']})
        return ok({'requested': True, 'note': note.name or None})

    @api_route('/api/v1/events/<int:event_id>/final', methods=('GET',))
    def final(self, employee, event_id, day=None, **kw):
        event = _mine(employee, event_id)
        data = _final(event, day)
        data['day_table'] = _day_table(event)
        return ok(data)

    # ---- PDFs: the phone's browser cannot send the app's token, so the link carries a signed one
    @api_route('/api/v1/events/<int:event_id>/pdf', methods=('POST',))
    def pdf_link(self, employee, event_id, **kw):
        event = _mine(employee, event_id)
        data = body()
        kind = data.get('kind') if data.get('kind') in ('final', 'distributor') else 'final'
        token = _sign({'e': employee.id, 'ev': event.id, 'pdf': kind, 'd': int(data.get('distributor_id') or 0),
                       'x': int(clock.time()) + LINK_SECONDS})
        return ok({'path': '/api/v1/events/pdf/download?t=%s' % token, 'expires_in': LINK_SECONDS})

    @http.route('/api/v1/events/pdf/download', type='http', auth='public', methods=['GET'], csrf=False,
                save_session=False)
    def pdf_download(self, t=None, **kw):
        payload = _unsign(t)
        if not payload or not payload.get('pdf'):
            return request.make_response('This download link has expired. Share again from the app.',
                                         headers=[('Content-Type', 'text/plain; charset=utf-8')], status=410)
        event = request.env['ff.event'].sudo().browse(payload['ev']).exists()
        if not event:
            return request.not_found()
        period = '%s - %s' % (event.date_start or '', event.date_end or '')
        if payload['pdf'] == 'distributor':
            rows = [r for r in _distributor_rows(event) if r['distributor']['id'] == payload.get('d')]
            if not rows:
                return request.not_found()
            row = rows[0]
            html = _html_table(
                row['distributor']['name'], '%s  |  %s' % (event.name, period),
                ['Flavour', 'Open', 'Add', 'Ret', 'Net taken', 'Samples', 'Damage', 'Closing', 'Sold', 'Sales ₹'],
                [[f['code'], '%g' % f['open'], '%g' % f['add'], '%g' % f['ret'], '%g' % f['net'], '%g' % f['samples'],
                  '%g' % f['damage'], '%g' % f['closing'], '%g' % f['sold'], '₹{:,.2f}'.format(f['sales'])]
                 for f in row['flavours']],
                ['Total'] + ['%g' % row['totals'][k] for k in ('open', 'add', 'ret', 'net', 'samples', 'damage', 'closing', 'sold')]
                + ['₹{:,.2f}'.format(row['totals']['sales'])],
                extra='<p style="font-size:12px">Coupons: %s (₹%s) &nbsp;|&nbsp; <b>Net sales: ₹{:,.2f}</b></p>'.format(
                    row['totals']['net_sales']) % (row['totals']['coupons'], row['totals']['coupon_amount']))
            name = 'Event_%s_%s.pdf' % (event.name.replace(' ', '_'), row['distributor']['name'].replace(' ', '_'))
        else:
            f = _final(event)
            day_table = _day_table(event)

            def _table_html(head, rows, foot=None):
                def cell(v, tag='td', bold=False, bg=None):
                    v_str = str(v)
                    is_num = v_str.replace('.', '').replace('-', '').replace(',', '').isdigit()
                    align = 'right' if is_num else 'left'
                    bg_style = 'background-color:%s;' % bg if bg else ''
                    return '<%s style="border:1px solid #999;padding:4px 8px;text-align:%s;%s">%s%s%s</%s>' % (
                        tag, align, bg_style, '<b>' if bold else '', v_str, '</b>' if bold else '', tag)
                head_row = '<tr>%s</tr>' % ''.join(cell(h, 'th', bold=True, bg='#f0f4f8') for h in head)
                body_rows = ''.join('<tr>%s</tr>' % ''.join(cell(c) for c in r) for r in rows)
                foot_row = ('<tr>%s</tr>' % ''.join(cell(c, bold=True, bg='#EEF3FB') for c in foot)) if foot else ''
                return '<table style="border-collapse:collapse;width:100%%;font-size:11px;margin-bottom:6px;">%s%s%s</table>' % (
                    head_row, body_rows, foot_row)

            # 1. Flavour-wise sales table
            flavour_head = ['Flavour', 'Opening', 'Added', 'Samples', 'Damage', 'Returned', 'Sold', 'MRP', 'Sales ₹']
            flavour_rows = [
                [r['code'], '%g' % r['opening'], '%g' % r['added'], '%g' % r['samples'], '%g' % r['damage'],
                 '%g' % r['returned'], '%g' % r['sold'], '₹%g' % r['mrp'], '₹{:,.2f}'.format(r['sales'])]
                for r in f['rows']
            ]
            flavour_foot = (
                ['Total'] + ['%g' % f['totals'][k] for k in ('opening', 'added', 'samples', 'damage', 'returned', 'sold')]
                + ['', '₹{:,.2f}'.format(f['sales'])]
            )
            t1_html = _table_html(flavour_head, flavour_rows, flavour_foot)
            note1 = '<div style="font-size:11px;color:#555;margin-bottom:18px;"><i>Sold = Opening + Added − Samples − Damage − Returned (closing 0 at the end).</i></div>'

            # 2. Day-wise reconciliation table
            day_head = ['Day', 'Sold', 'Sales ₹', 'Coupons ₹', 'Net sales', 'Cash', 'UPI ₹']
            day_rows = [
                ['Day %s' % (i + 1), '%g' % d['sold'], '₹{:,.2f}'.format(d['sales']),
                 ('- ₹{:,.2f}'.format(d['coupons_amount'])) if d['coupons_amount'] else '₹0.00',
                 '₹{:,.2f}'.format(d['net_sales']),
                 ('- ₹{:,.2f}'.format(d['cash'])) if d['cash'] else '₹0.00',
                 '₹{:,.2f}'.format(d['upi'])]
                for i, d in enumerate(day_table)
            ]
            day_foot = [
                'Total', '%g' % f['totals']['sold'], '₹{:,.2f}'.format(f['sales']),
                ('- ₹{:,.2f}'.format(f['coupon_amount'])) if f['coupon_amount'] else '₹0.00',
                '₹{:,.2f}'.format(f['net_sales']),
                ('- ₹{:,.2f}'.format(f['cash'])) if f['cash'] else '₹0.00',
                '₹{:,.2f}'.format(f['upi'])
            ]
            t2_html = _table_html(day_head, day_rows, day_foot)
            note2 = '<div style="font-size:11px;color:#166534;background:#E6F7EC;border:1px solid #86D9A3;padding:6px 10px;border-radius:4px;margin-top:6px;margin-bottom:18px;"><b>UPI ₹ for each day should match the bank credit for that day.</b></div>'

            # 3. Financial summary
            summary_html = (
                '<h3 style="margin:16px 0 6px 0;font-size:13px;">Reconciliation Summary</h3>'
                '<table style="border-collapse:collapse;font-size:11px;min-width:320px;">'
                '<tr><td style="padding:4px 12px 4px 0;">Sales amount flavour-wise total</td><td align="right" style="padding:4px 0;"><b>₹{:,.2f}</b></td></tr>'
                '<tr><td style="padding:4px 12px 4px 0;">Less: Coupons %s × ₹%g</td><td align="right" style="padding:4px 0;">- ₹{:,.2f}</td></tr>'
                '<tr style="border-top:1px solid #999;border-bottom:1px solid #999;"><td style="padding:4px 12px 4px 0;"><b>Net sales</b></td><td align="right" style="padding:4px 0;"><b>₹{:,.2f}</b></td></tr>'
                '<tr><td style="padding:4px 12px 4px 0;">Less: Cash received</td><td align="right" style="padding:4px 0;">- ₹{:,.2f}</td></tr>'
                '<tr style="background:#E6F7EC;"><td style="padding:6px 10px;border:1px solid #86D9A3;"><b>UPI received</b></td><td align="right" style="padding:6px 10px;border:1px solid #86D9A3;"><b>₹{:,.2f}</b></td></tr>'
                '</table>'
            ).format(
                f['sales'], f['coupons'], f['coupon_value'], f['coupon_amount'],
                f['net_sales'], f['cash'], f['upi']
            )

            html = (
                '<html><head><meta charset="utf-8"/></head><body style="font-family:Arial, sans-serif;font-size:12px;padding:10px;">'
                '<h2 style="margin:0 0 4px 0;">Final report - %s</h2>'
                '<div style="color:#555;margin-bottom:16px;">%s  |  %s</div>'
                '<h3 style="margin:0 0 6px 0;font-size:13px;">Flavour-wise Sales</h3>'
                '%s%s'
                '<h3 style="margin:16px 0 6px 0;font-size:13px;">Day-wise Reconciliation</h3>'
                '%s%s%s'
                '</body></html>' % (
                    event.name,
                    event.price_category_id.name or '',
                    period,
                    t1_html, note1,
                    t2_html, note2, summary_html
                )
            )
            name = 'Event_%s_final_report.pdf' % event.name.replace(' ', '_')
        try:
            content = _pdf(html)
        except ApiError as error:
            return request.make_response(str(error), headers=[('Content-Type', 'text/plain; charset=utf-8')], status=400)
        return request.make_response(content, headers=[
            ('Content-Type', 'application/pdf'),
            ('Content-Disposition', 'attachment; filename="%s"' % name),
            ('Content-Length', str(len(content))),
        ])
