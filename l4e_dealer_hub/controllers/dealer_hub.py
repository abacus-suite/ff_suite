"""The Dealer Hub: a distributor's own view of the business, behind a login."""
import io
from collections import OrderedDict
from datetime import date, datetime, timedelta
from urllib.parse import parse_qsl, urlencode

from odoo import fields, http
from odoo.http import request

NAV = OrderedDict([
    ('dashboard', ('Dashboard', 'fa-th-large', '/dealer', 'teal')),
    ('requests', ('Outlet PO', 'fa-file-text-o', '/dealer/requests', 'teal')),
    ('deliveries', ('Deliveries', 'fa-truck', '/dealer/deliveries', 'teal')),
    ('outlets', ('Outlets', 'fa-home', '/dealer/outlets', 'teal')),
    ('outlets_outstanding', ('Outlet Outstanding', 'fa-clipboard', '/dealer/outlets/outstanding', 'teal')),
    ('collections', ('Payment Collection', 'fa-money', '/dealer/collections', 'teal')),
    ('foc', ('Samples', 'fa-gift', '/dealer/foc', 'teal')),
    ('orders', ('PO to Kumbayah Foods', 'fa-shopping-cart', '/dealer/orders', 'purple')),
    ('invoices', ('Invoice from Kumbayah Foods', 'fa-file-text', '/dealer/invoices', 'purple')),
    ('returns', ('Debit/Credit Notes to Kumbayah Foods', 'fa-credit-card', '/dealer/returns', 'purple')),
    ('stock', ('Stock', 'fa-archive', '/dealer/stock', 'blue')),
])

PRESETS = [('today', 'Today'), ('week', 'This week'), ('month', 'This month'), ('quarter', '3 months'),
           ('year', 'This year'), ('all', 'All time')]


def money(value):
    return '₹{:,.2f}'.format(value or 0.0)


def qty(value):
    return '%g' % round(value or 0.0, 3)


def step(product):
    """The smallest amount the product's unit of measure allows, as a number input step."""
    rounding = product.uom_id.rounding or 1.0
    return ('%.6f' % rounding).rstrip('0').rstrip('.') or '1'


def cell(text, tone=None, bold=False, align=None, href=None):
    return {'t': text, 'tone': tone, 'bold': bold, 'align': align, 'href': href}


def _day(text):
    try:
        return datetime.strptime(text, '%Y-%m-%d').date()
    except (TypeError, ValueError):
        return None


def preset_range(key):
    today = date.today()
    if key == 'today':
        return today, today
    if key == 'week':
        return today - timedelta(days=today.weekday()), today
    if key == 'month':
        return today.replace(day=1), today
    if key == 'quarter':
        return (today.replace(day=1) - timedelta(days=61)).replace(day=1), today
    if key == 'year':
        return today.replace(month=1, day=1), today
    return None, None


class Filter:
    """The date range asked for, and the links that keep it while moving around."""

    def __init__(self, kw, default='all'):
        self.kw = {k: v for k, v in kw.items() if v not in (None, '')}
        start, end = _day(self.kw.get('date_from')), _day(self.kw.get('date_to'))
        self.period = self.kw.get('period')
        if not (start or end):
            self.period = self.period or default
            start, end = preset_range(self.period)
        else:
            self.period = 'custom'
        self.start, self.end = start, end
        self.start_dt = datetime.combine(start, datetime.min.time()) if start else None
        self.end_dt = datetime.combine(end + timedelta(days=1), datetime.min.time()) if end else None

    @property
    def label(self):
        if self.period != 'custom':
            return dict(PRESETS).get(self.period, 'All time')
        return '%s to %s' % (self.start.strftime('%d %b %Y') if self.start else 'start',
                             self.end.strftime('%d %b %Y') if self.end else 'today')

    def link(self, path='', **change):
        params = {k: v for k, v in self.kw.items() if k not in ('period', 'date_from', 'date_to')}
        if self.period == 'custom':
            params['date_from'] = self.start.isoformat() if self.start else ''
            params['date_to'] = self.end.isoformat() if self.end else ''
        else:
            params['period'] = self.period
        params.update(change)
        params = {k: v for k, v in params.items() if v not in (None, '')}
        return '%s?%s' % (path, urlencode(params)) if params else path

    def presets(self, path):
        return [{'key': k, 'label': v, 'on': self.period == k,
                 'href': self.link(path, period=k, date_from='', date_to='', page=None)} for k, v in PRESETS]

    def has(self, moment):
        if not moment:
            return not (self.start_dt or self.end_dt)
        if isinstance(moment, date) and not isinstance(moment, datetime):
            moment = datetime.combine(moment, datetime.min.time())
        return (not self.start_dt or moment >= self.start_dt) and (not self.end_dt or moment < self.end_dt)


def make_pager(flt, path, total_count, page=1, limit=50, search=None):
    total_pages = max(1, (total_count + limit - 1) // limit)
    page = max(1, min(page, total_pages))
    offset = (page - 1) * limit

    pages_to_show = set()
    pages_to_show.add(1)
    pages_to_show.add(total_pages)
    for p in range(max(1, page - 2), min(total_pages + 1, page + 3)):
        pages_to_show.add(p)

    sorted_pages = sorted(pages_to_show)
    page_items = []
    prev_p = 0
    for p in sorted_pages:
        if prev_p and p - prev_p > 1:
            page_items.append({'num': '...', 'url': None, 'active': False, 'is_gap': True})
        page_items.append({
            'num': p,
            'url': flt.link(path, page=p if p > 1 else None, search=search or '') if flt else '%s?page=%s' % (path, p),
            'active': p == page,
            'is_gap': False,
        })
        prev_p = p

    return {
        'page': page,
        'page_count': total_pages,
        'total': total_count,
        'limit': limit,
        'offset_start': offset + 1 if total_count else 0,
        'offset_end': min(offset + limit, total_count),
        'has_prev': page > 1,
        'has_next': page < total_pages,
        'prev_url': flt.link(path, page=(page - 1) if (page - 1) > 1 else None, search=search or '') if (flt and page > 1) else None,
        'next_url': flt.link(path, page=page + 1, search=search or '') if (flt and page < total_pages) else None,
        'pages': page_items,
    }


class DealerHub(http.Controller):

    # ------------------------------------------------------------------
    # Who is looking
    # ------------------------------------------------------------------
    def _dealer(self, preview=None):
        """The distributor this visitor is: their own contact, or one a manager previews."""
        user = request.env.user
        if user._is_public():
            return None
        if not user.share and preview and (user.has_group('ff_base.group_ff_manager') or user.has_group('base.group_system')):
            partner = request.env['res.partner'].sudo().browse(int(preview)).exists()
            return partner if partner and partner.ff_is_distributor else None
        partner = user.partner_id.commercial_partner_id
        return partner if partner.ff_is_distributor else None

    def _gate(self, preview):
        dealer = self._dealer(preview)
        if dealer:
            return dealer, None
        if request.env.user._is_public():
            return None, request.redirect('/dealer/login')
        return None, request.render('l4e_dealer_hub.hub_no_access', {})

    def _ctx(self, dealer, nav, preview, flt=None, path='/dealer', **extra):
        company = (dealer and dealer.company_id) or request.env.company
        values = {
            'dealer': dealer, 'nav': nav, 'items': NAV, 'preview': preview,
            'company': company,
            'q': ('?as=%s' % preview) if preview else '', 'user_name': request.env.user.name,
            'flt': flt, 'flt_presets': flt.presets(path) if flt else [], 'flt_path': path,
        }
        values.update(extra)
        return values

    # ------------------------------------------------------------------
    # Sign in
    # ------------------------------------------------------------------
    @http.route('/dealer/login', type='http', auth='public', website=True, sitemap=False)
    def login(self, error=None, **kw):
        if not request.env.user._is_public():
            return request.redirect('/dealer')
        return request.render('l4e_dealer_hub.hub_login', {'error': error})

    # ------------------------------------------------------------------
    # Dashboard
    # ------------------------------------------------------------------
    @http.route('/dealer', type='http', auth='public', website=True, sitemap=False)
    def dashboard(self, **kw):
        preview = kw.get('as')
        dealer, bounce = self._gate(preview)
        if bounce:
            return bounce
        flt = Filter(kw, default='month')
        env = request.env
        Demand = env['ff.demand'].sudo()
        Request = env['ff.demand.request'].sudo()
        Invoice = env['ff.outlet.invoice'].sudo()
        dom = [('distributor_id', '=', dealer.id)]
        if flt.start_dt:
            dom.append(('date', '>=', flt.start_dt))
        if flt.end_dt:
            dom.append(('date', '<', flt.end_dt))
        demands = Demand.search(dom)
        waiting = Request.search_count([('partner_id', '=', dealer.id), ('state', '=', 'sent')])
        inv_dom = [('distributor_id', '=', dealer.id), ('cancelled', '=', False)]
        if flt.start:
            inv_dom.append(('date', '>=', flt.start))
        if flt.end:
            inv_dom.append(('date', '<=', flt.end))
        invoices = Invoice.search(inv_dom)

        counts = OrderedDict([
            ('Waiting for you', (len(demands.filtered(lambda d: d.state == 'waiting')), '#f59e0b')),
            ('In progress', (len(demands.filtered(lambda d: d.delivery_status_id.code == 'progress')), '#3b82f6')),
            ('Partially delivered', (len(demands.filtered(lambda d: d.delivery_status_id.code == 'partial')), '#a855f7')),
            ('Fully delivered', (len(demands.filtered(lambda d: d.state == 'supplied')), '#16a34a')),
            ('Rejected', (len(demands.filtered(lambda d: d.state == 'rejected')), '#ef4444')),
        ])
        total = sum(v[0] for v in counts.values()) or 1
        stops, at = [], 0.0
        for label, (n, colour) in counts.items():
            share = n / total * 100.0
            if share:
                stops.append('%s %.2f%% %.2f%%' % (colour, at, at + share))
            at += share
        donut = 'conic-gradient(%s)' % (', '.join(stops) if stops else '#e2e8f0 0 100%')

        # six months up to the end of the range: delivered and collected
        last = (flt.end or date.today()).replace(day=1)
        months = []
        for i in range(5, -1, -1):
            month = last
            for _ in range(i):
                month = (month - timedelta(days=1)).replace(day=1)
            months.append(month)
        first = datetime.combine(months[0], datetime.min.time())
        delivered, collected = {}, {}
        for d in env['ff.demand.delivery'].sudo().search([('distributor_id', '=', dealer.id), ('date', '>=', first)]):
            key = d.date.date().replace(day=1)
            delivered[key] = delivered.get(key, 0.0) + d.amount
        for p in env['ff.outlet.payment'].sudo().search(
                [('distributor_id', '=', dealer.id), ('state', '=', 'confirmed'), ('date', '>=', first)]):
            key = p.date.date().replace(day=1)
            collected[key] = collected.get(key, 0.0) + p.amount
        peak = max(list(delivered.values()) + list(collected.values()) + [1.0])
        trend = [{
            'label': m.strftime('%b'), 'd': delivered.get(m, 0.0), 'c': collected.get(m, 0.0),
            'dh': round(delivered.get(m, 0.0) / peak * 100, 1), 'ch': round(collected.get(m, 0.0) / peak * 100, 1),
        } for m in months]

        owed = 0.0
        if 'account.move' in env:
            moves = env['account.move'].sudo().search([
                ('partner_id', 'child_of', dealer.id), ('move_type', '=', 'out_invoice'),
                ('state', '=', 'posted'), ('payment_state', 'in', ('not_paid', 'partial'))])
            owed = sum(moves.mapped('amount_residual'))

        on_hand = env['l4e.dealer.stock.move'].ff_on_hand(dealer)
        recent = Request.search([('partner_id', '=', dealer.id)], limit=6)
        today_date = date.today()
        overdue_invoices = invoices.filtered(lambda i: i.due_date and i.due_date < today_date and i.state in ('open', 'partial'))
        out_for_delivery_demands = demands.filtered(lambda d: d.delivery_status_id.code in ('progress', 'partial'))

        return request.render('l4e_dealer_hub.hub_dashboard', self._ctx(
            dealer, 'dashboard', preview, flt=flt, path='/dealer', waiting=waiting,
            kpis={
                'demands': len(demands), 'demand_value': sum(demands.mapped('amount_total')),
                'delivered_value': sum(demands.mapped('delivered_amount')),
                'in_delivery': len(demands.filtered(lambda d: d.state == 'approved')),
                'out_for_delivery': len(out_for_delivery_demands),
                'outlets': env['res.partner'].sudo().search_count([('ff_distributor_id', '=', dealer.id)]),
                'billed': sum(invoices.mapped('amount_total')),
                'collected': sum(invoices.mapped('amount_confirmed')),
                'awaiting': sum(invoices.mapped('amount_awaiting')),
                'pending': sum(invoices.mapped('amount_pending')),
                'overdue_amount': sum(overdue_invoices.mapped('amount_pending')),
                'owed': owed, 'stock_units': sum(v for v in on_hand.values() if v > 0),
                'stock_items': len([v for v in on_hand.values() if v > 0]),
            },
            counts=counts, donut=donut, total_demands=sum(v[0] for v in counts.values()), trend=trend,
            recent=recent, money=money))

    # ------------------------------------------------------------------
    # The list pages, built the same way
    # ------------------------------------------------------------------
    def _table(self, dealer, nav, preview, flt, path, title, subtitle, columns, rows, tabs=None, active=None,
               search=None, summary=None, empty='Nothing here yet.', dates=True, export=None, action=None, main_tabs=None, pager=None):
        for tab in tabs or []:
            tab['href'] = flt.link(path, state=tab['key'], search=search or '', page=None)
        if export:
            target, _sep, query = export.partition('?')
            extra = dict(parse_qsl(query))
            if active and active != 'all':
                extra['state'] = active
            export = flt.link(target, search=search or '', **extra)
        return request.render('l4e_dealer_hub.hub_table', self._ctx(
            dealer, nav, preview, flt=flt, path=path, title=title, subtitle=subtitle, columns=columns, rows=rows,
            tabs=tabs or [], active=active, search=search, summary=summary or [], empty=empty, dates=dates,
            export=export, action=action, main_tabs=main_tabs or [], pager=pager))

    @http.route('/dealer/requests', type='http', auth='public', website=True, sitemap=False)
    def requests_page(self, state='all', search=None, **kw):
        preview = kw.get('as')
        dealer, bounce = self._gate(preview)
        if bounce:
            return bounce

        # Normalize filter state aliases
        if state in ('sent', 'to_approve'):
            state = 'to_approve'
        elif state in ('done', 'delivered'):
            state = 'delivered'
        elif state in ('rejected', 'cancel', 'cancelled'):
            state = 'cancelled'

        flt = Filter(dict(kw, state=state if state != 'all' else None, search=search))
        records = request.env['ff.demand.request'].sudo().search(
            [('partner_id', '=', dealer.id)], limit=500).filtered(lambda r: flt.has(r.date_order))

        def stage(r):
            if r.state in ('rejected', 'cancel'):
                return 'cancelled'
            if r.state == 'sent':
                return 'to_approve'
            if r.state == 'done' or (r.approved_total > 0 and r.delivered_total >= r.approved_total - 0.01):
                return 'delivered'
            if r.delivered_total > 0 or any(d.delivery_ids for d in r.demand_ids):
                return 'out_for_delivery'
            return 'to_deliver'

        names = OrderedDict([
            ('to_approve', ('PO to Approve', 'warn')),
            ('to_deliver', ('PO to Deliver', 'info')),
            ('out_for_delivery', ('Out for Delivery', 'delivery')),
            ('delivered', ('Delivered', 'good')),
            ('cancelled', ('Cancelled', 'bad')),
        ])
        tabs = [{'key': 'all', 'label': 'All', 'n': len(records)}] + [
            {'key': k, 'label': v[0], 'n': len(records.filtered(lambda r, k=k: stage(r) == k))}
            for k, v in names.items()]
        if state != 'all':
            records = records.filtered(lambda r: stage(r) == state)
        if search:
            search_str = search.lower()
            records = records.filtered(
                lambda r: search_str in (r.name or '').lower()
                or search_str in (r.origin or '').lower()
                or (r.ff_employee_id and search_str in (r.ff_employee_id.name or '').lower())
                or any(search_str in (d.partner_id.name or '').lower() for d in r.demand_ids)
            )
        rows = []
        for r in records:
            label, tone = names[stage(r)]
            link = '/dealer/requests/%s%s' % (r.id, ('?as=%s' % preview) if preview else '')
            rows.append([
                cell(r.name, bold=True, href=link),
                cell(r.date_order.strftime('%d %b %Y') if r.date_order else ''),
                cell(str(r.demand_count), align='center'),
                cell(money(r.amount_total), align='end'),
                cell(money(r.approved_total), align='end'),
                cell(money(r.delivered_total), align='end'),
                cell(label, tone=tone),
                cell('Review' if r.state == 'sent' else 'Open', tone='info', href=link),
            ])
        return self._table(
            dealer, 'requests', preview, flt, '/dealer/requests', 'Outlet PO',
            'Approve what the outlets asked for, then record the deliveries.',
            ['Request', 'Date', 'Outlets', 'Asked', 'Approved', 'Delivered', 'Status', ''], rows,
            tabs=tabs, active=state, search=search, empty='No demand has been sent to you in this period.')

    @http.route('/dealer/orders', type='http', auth='public', website=True, sitemap=False)
    def orders_page(self, state='all', search=None, **kw):
        """The orders our sales team took from this distributor, and where each stands. View only."""
        preview = kw.get('as')
        dealer, bounce = self._gate(preview)
        if bounce:
            return bounce
        flt = Filter(dict(kw, state=state if state != 'all' else None, search=search))
        orders = request.env['sale.order'].sudo().search(
            [('partner_id', 'child_of', dealer.id), ('state', 'in', ('draft', 'sent', 'sale', 'done', 'cancel'))],
            order='date_order desc', limit=500).filtered(lambda o: flt.has(o.date_order))

        def stage(o):
            if o.state == 'cancel' or getattr(o, 'distributor_status', False) == 'rejected':
                return 'cancelled'
            if o.invoice_status == 'invoiced':
                return 'invoiced'
            if getattr(o, 'delivery_status', False) == 'full':
                return 'delivered'
            if getattr(o, 'distributor_status', False) == 'pending' or o.state in ('draft', 'sent'):
                return 'to_approve'
            return 'approved'

        names = OrderedDict([
            ('to_approve', ('To Approve', 'warn')),
            ('approved', ('Approved', 'info')),
            ('invoiced', ('Invoiced', 'good')),
            ('delivered', ('Delivered', 'good')),
            ('cancelled', ('Cancelled', 'bad')),
        ])
        tabs = [{'key': 'all', 'label': 'All', 'n': len(orders)}] + [
            {'key': k, 'label': v[0], 'n': len(orders.filtered(lambda o, k=k: stage(o) == k))} for k, v in names.items()]
        if state != 'all':
            orders = orders.filtered(lambda o: stage(o) == state)
        if search:
            search_str = search.lower()
            orders = orders.filtered(lambda o: search_str in (o.name or '').lower() or any(search_str in (inv.name or '').lower() for inv in o.invoice_ids))
        rows = []
        for o in orders:
            label, tone = names[stage(o)]
            invoices = o.invoice_ids.filtered(lambda m: m.state == 'posted')
            rows.append([
                cell(o.name, bold=True, href='/dealer/orders/%s%s' % (o.id, ('?as=%s' % preview) if preview else '')),
                cell(o.date_order.strftime('%d %b %Y') if o.date_order else ''),
                cell('%g' % sum(o.order_line.filtered(lambda l: not l.display_type).mapped('product_uom_qty')), align='center'),
                cell(money(o.amount_total), align='end'),
                cell(', '.join(invoices.mapped('name')) or '-'),
                cell(label, tone=tone),
            ])
        return self._table(
            dealer, 'orders', preview, flt, '/dealer/orders', 'PO to Kumbayah Foods',
            'Orders taken for you by our sales team. We deliver and invoice them; you can follow the status here.',
            ['Order', 'Date', 'Units', 'Amount', 'Invoice', 'Status'], rows, tabs=tabs, active=state, search=search,
            empty='No order in this period.')

    def _own_request(self, request_id, preview):
        dealer, bounce = self._gate(preview)
        if bounce:
            return None, None, bounce
        req = request.env['ff.demand.request'].sudo().browse(request_id).exists()
        if not req or req.partner_id != dealer:
            return dealer, None, request.redirect('/dealer/requests' + ('?as=%s' % preview if preview else ''))
        return dealer, req, None

    @staticmethod
    def _request_pricing(req):
        """How each outlet's price is made and what it means for the distributor, so it is clear before approving.

        Per outlet: MRP, less the scheme per bottle, less the outlet's margin, the rate. Then the distributor's
        side: what it buys at (MRP less the total margin), what it is invoiced to the outlet for, and the debit
        note the company makes good when the outlet was promised more than the distributor normally passes on.
        """
        out = []
        for demand in req.demand_ids:
            lines = demand.line_ids.filtered(lambda l: not getattr(l, 'is_foc', False) and l.quantity)
            if not lines:
                continue
            outlet = demand.partner_id.sudo().commercial_partner_id
            option = outlet.ff_scheme_id if 'ff_scheme_id' in outlet._fields else False
            scheme = option.ff_scheme_value() if option and hasattr(option, 'ff_scheme_value') else 0.0
            margin = getattr(demand, 'margin_outlet', 0.0) or outlet.ff_margin or 0.0
            total = getattr(demand, 'margin_total', 0.0) or 0.0
            excess = getattr(demand, 'margin_excess', 0.0) or 0.0
            rows, mrp_value, billed = [], 0.0, 0.0
            for line in lines:
                mrp = line.product_id.product_tmpl_id.ff_mrp or 0.0
                after = max(mrp - scheme, 0.0)
                worked = round(after * (1.0 - margin / 100.0), 2) if mrp else line.price_unit
                rows.append({
                    'name': line.product_id.display_name, 'qty': line.quantity, 'mrp': mrp, 'scheme': scheme,
                    'after': after, 'margin_amount': round(after * margin / 100.0, 2),
                    'rate': line.price_unit, 'worked': worked, 'differs': abs(worked - line.price_unit) > 0.01,
                    'amount': round(line.price_unit * line.quantity, 2),
                })
                mrp_value += mrp * line.quantity
                billed += line.price_unit * line.quantity
            buy = round(mrp_value * (1.0 - total / 100.0), 2) if total else 0.0
            note = round(mrp_value * excess / 100.0, 2)
            out.append({
                'outlet': demand.partner_id.display_name, 'scheme': scheme, 'margin': margin, 'total': total,
                'excess': excess, 'rows': rows, 'billed': round(billed, 2), 'buy': buy, 'note': note,
                'net': round(billed + note - buy, 2) if total else None,
            })
        return out

    @http.route('/dealer/requests/<int:request_id>', type='http', auth='public', website=True, sitemap=False)
    def request_page(self, request_id, **kw):
        preview = kw.get('as')
        dealer, req, bounce = self._own_request(request_id, preview)
        if bounce:
            return bounce
        from odoo.addons.l4e_distributor_portal.controllers.distributor_portal import request_lines, request_outlets
        approved = req.state in ('approved', 'done')
        return request.render('l4e_dealer_hub.hub_request', self._ctx(
            dealer, 'requests', preview, req=req, lines=request_lines(req), outlets=request_outlets(req),
            pricing=self._request_pricing(req),
            deliveries=req.ff_deliveries() if approved else [], money=money, qty=qty,
            notes=req.demand_ids.mapped('note_ids') if 'note_ids' in request.env['ff.demand']._fields else [],
            saved=kw.get('saved'), error=kw.get('error')))

    @http.route('/dealer/requests/<int:request_id>/approve', type='http', auth='public', website=True,
                methods=['POST'], sitemap=False)
    def request_approve(self, request_id, **post):
        preview = post.get('as')
        dealer, req, bounce = self._own_request(request_id, preview)
        if bounce:
            return bounce
        back = '/dealer/requests/%s?%s' % (req.id, urlencode({'as': preview} if preview else {}))
        if req.state == 'sent':
            quantities = {}
            for key in request.httprequest.form.getlist('line_ids[]'):
                try:
                    rid = int(key)
                    quantities[rid] = float(post.get('qty_%s' % rid))
                except (TypeError, ValueError):
                    continue
            try:
                req.ff_reject(post.get('notes')) if post.get('decision') == 'reject' else req.ff_approve(quantities, post.get('notes'))
            except Exception as error:  # noqa: BLE001 - said on the page
                return request.redirect(back + '&' + urlencode({'error': str(error)}))
        return request.redirect(back + '&saved=1')

    @http.route('/dealer/requests/<int:request_id>/deliver', type='http', auth='public', website=True,
                methods=['POST'], sitemap=False)
    def request_deliver(self, request_id, **post):
        preview = post.get('as')
        dealer, req, bounce = self._own_request(request_id, preview)
        if bounce:
            return bounce
        back = '/dealer/requests/%s?%s' % (req.id, urlencode({'as': preview} if preview else {}))
        demand = req.demand_ids.filtered(lambda d: d.id == int(post.get('demand_id') or 0))
        if not demand:
            return request.redirect(back)
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
                demand.ff_record_delivery(quantities, post.get('note'), entered_by=dealer.name)
        except Exception as error:  # noqa: BLE001 - said on the page
            return request.redirect(back + '&' + urlencode({'error': str(error)}))
        return request.redirect(back + '&saved=1')

    @http.route('/dealer/orders/<int:order_id>', type='http', auth='public', website=True, sitemap=False)
    def order_page(self, order_id, **kw):
        """An order taken for the distributor: shown in full, nothing to change."""
        preview = kw.get('as')
        dealer, bounce = self._gate(preview)
        if bounce:
            return bounce
        order = request.env['sale.order'].sudo().browse(order_id).exists()
        if not order or order.partner_id.commercial_partner_id != dealer:
            return request.redirect('/dealer/orders' + ('?as=%s' % preview if preview else ''))
        invoices = order.invoice_ids.filtered(lambda m: m.state == 'posted')
        pickings = order.picking_ids if 'picking_ids' in order._fields else request.env['stock.picking']
        return request.render('l4e_dealer_hub.hub_order', self._ctx(
            dealer, 'orders', preview, order=order, invoices=invoices, pickings=pickings, money=money, qty=qty))

    @http.route('/dealer/deliveries', type='http', auth='public', website=True, sitemap=False)
    def deliveries_page(self, state='to_deliver', search=None, **kw):
        preview = kw.get('as')
        dealer, bounce = self._gate(preview)
        if bounce:
            return bounce

        # Normalize filter state aliases
        if state in ('open', 'to_deliver'):
            state = 'to_deliver'
        elif state in ('done', 'delivered'):
            state = 'delivered'

        flt = Filter(dict(kw, state=state if state != 'all' else None, search=search))
        demands = request.env['ff.demand'].sudo().search(
            [('distributor_id', '=', dealer.id), ('state', 'in', ('approved', 'supplied'))],
            limit=600).filtered(lambda d: flt.has(d.date))

        def stage(d):
            if d.state == 'supplied' or getattr(d.delivery_status_id, 'code', False) == 'full' or (d.approved_quantity > 0 and d.delivered_quantity >= d.approved_quantity - 0.001):
                return 'delivered'
            if getattr(d.delivery_status_id, 'code', False) == 'partial' or d.delivered_quantity > 0:
                return 'out_for_delivery'
            return 'to_deliver'

        tabs = [
            {'key': 'all', 'label': 'All', 'n': len(demands)},
            {'key': 'to_deliver', 'label': 'To Deliver', 'n': len(demands.filtered(lambda d: stage(d) == 'to_deliver'))},
            {'key': 'out_for_delivery', 'label': 'Out for Delivery', 'n': len(demands.filtered(lambda d: stage(d) == 'out_for_delivery'))},
            {'key': 'delivered', 'label': 'Delivered', 'n': len(demands.filtered(lambda d: stage(d) == 'delivered'))},
        ]

        if state != 'all':
            demands = demands.filtered(lambda d: stage(d) == state)
        if search:
            demands = demands.filtered(lambda d: search.lower() in ((d.name or '') + (d.partner_id.name or '')).lower())
        rows = []
        for d in demands:
            req = d.request_id
            link = ('/dealer/requests/%s%s' % (req.id, ('?as=%s' % preview) if preview else '')) if req else None
            st = stage(d)
            code = getattr(d.delivery_status_id, 'code', False)
            tone = {'progress': 'info', 'partial': 'warn', 'full': 'good'}.get(code, 'good' if st == 'delivered' else 'mute')
            rows.append([
                cell(d.partner_id.display_name, bold=True, href=link),
                cell(d.name),
                cell(qty(d.approved_quantity), align='center'),
                cell(qty(d.delivered_quantity), align='center'),
                cell(money(d.delivered_amount), align='end'),
                cell(d.delivery_status_id.name or ('Delivered' if st == 'delivered' else '-'), tone=tone),
                cell('Record delivery' if d.state == 'approved' else 'View', tone='info', href=link),
            ])
        empty_msg = 'No approved demand is waiting for delivery.' if state == 'to_deliver' else 'No deliveries found in this period.'
        return self._table(
            dealer, 'deliveries', preview, flt, '/dealer/deliveries', 'Deliveries',
            'What was approved, and what has reached each outlet.',
            ['Outlet', 'Demand', 'Approved', 'Delivered', 'Billed to outlet', 'Status', ''], rows,
            tabs=tabs, active=state, search=search, empty=empty_msg)

    @http.route(['/dealer/outlets', '/dealer/outlets/page/<int:page>'], type='http', auth='public', website=True, sitemap=False)
    def outlets_page(self, page=1, search=None, **kw):
        preview = kw.get('as')
        dealer, bounce = self._gate(preview)
        if bounce:
            return bounce
        try:
            page = int(kw.get('page') or page or 1)
        except (ValueError, TypeError):
            page = 1
        page = max(1, page)
        limit = 50

        flt = Filter(dict(kw, search=search))
        env = request.env
        domain = [('ff_distributor_id', '=', dealer.id)]
        if search:
            domain += ['|', '|', ('name', 'ilike', search), ('city', 'ilike', search), ('ref', 'ilike', search)]
        all_outlets = env['res.partner'].sudo().search(domain, order='name')
        total_count = len(all_outlets)

        pager = make_pager(flt, '/dealer/outlets', total_count, page=page, limit=limit, search=search)
        page = pager['page']
        offset = (page - 1) * limit
        paged_outlets = all_outlets[offset:offset + limit]

        demands = env['ff.demand'].sudo().search([('distributor_id', '=', dealer.id)]).filtered(lambda d: flt.has(d.date))
        invoices = env['ff.outlet.invoice'].sudo().search([('distributor_id', '=', dealer.id), ('cancelled', '=', False)])
        rows = []
        for outlet in paged_outlets:
            mine = demands.filtered(lambda d: d.partner_id == outlet)
            owed = sum(invoices.filtered(lambda i: i.partner_id == outlet).mapped('amount_pending'))
            rows.append([
                cell(outlet.display_name, bold=True), cell(outlet.ref or ''), cell(outlet.city or ''),
                cell(str(len(mine)), align='center'), cell(money(sum(mine.mapped('delivered_amount'))), align='end'),
                cell(money(owed), align='end', tone='bad' if owed else None),
            ])
        return self._table(
            dealer, 'outlets', preview, flt, '/dealer/outlets', 'Outlets (%d)' % total_count,
            'The outlets you supply, what you delivered to them in the period and what they still owe.',
            ['Outlet', 'Code', 'City', 'Demands', 'Delivered', 'Outstanding'], rows, search=search,
            pager=pager,
            empty='No outlet is linked to you yet.')

    @http.route(['/dealer/outlets/outstanding', '/dealer/outlets/outstanding/page/<int:page>'], type='http', auth='public', website=True, sitemap=False)
    def outlets_outstanding_page(self, page=1, search=None, **kw):
        preview = kw.get('as')
        dealer, bounce = self._gate(preview)
        if bounce:
            return bounce
        try:
            page = int(kw.get('page') or page or 1)
        except (ValueError, TypeError):
            page = 1
        page = max(1, page)
        limit = 50

        flt = Filter(dict(kw, search=search))
        env = request.env
        outlets = env['res.partner'].sudo().search([('ff_distributor_id', '=', dealer.id)], order='name')
        invoices = env['ff.outlet.invoice'].sudo().search([
            ('distributor_id', '=', dealer.id), ('cancelled', '=', False), ('state', 'in', ('open', 'partial'))])

        # Only outlets that have outstanding amounts
        all_rows = []
        total_outstanding = 0.0
        for outlet in outlets:
            owed = sum(invoices.filtered(lambda i: i.partner_id == outlet).mapped('amount_pending'))
            if owed <= 0:
                continue
            total_outstanding += owed
            if search and search.lower() not in ((outlet.name or '') + (outlet.city or '') + (outlet.ref or '')).lower():
                continue
            all_rows.append([
                cell(outlet.display_name, bold=True), cell(outlet.ref or ''), cell(outlet.city or ''),
                cell(money(owed), align='end', tone='bad', bold=True),
            ])
        total_count = len(all_rows)
        pager = make_pager(flt, '/dealer/outlets/outstanding', total_count, page=page, limit=limit, search=search)
        page = pager['page']
        offset = (page - 1) * limit
        rows = all_rows[offset:offset + limit]

        return self._table(
            dealer, 'outlets_outstanding', preview, flt, '/dealer/outlets/outstanding', 'Outlet Outstanding (%d)' % total_count,
            'Outlets with pending balances and the amount yet to be collected.',
            ['Outlet', 'Code', 'City', 'Outstanding Amount'], rows, search=search,
            summary=[('Total Outlet Outstanding', money(total_outstanding))],
            pager=pager,
            empty='No outstanding balance pending from outlets.')

    @http.route('/dealer/invoices', type='http', auth='public', website=True, sitemap=False)
    def invoices_page(self, state='all', search=None, **kw):
        preview = kw.get('as')
        dealer, bounce = self._gate(preview)
        if bounce:
            return bounce
        flt = Filter(dict(kw, state=state if state != 'all' else None, search=search))
        env = request.env
        moves = env['account.move'].sudo().browse() if 'account.move' not in env else env['account.move'].sudo().search([
            ('partner_id', 'child_of', dealer.id), ('move_type', '=', 'out_invoice'), ('state', '=', 'posted')],
            order='invoice_date desc, id desc', limit=500).filtered(lambda m: flt.has(m.invoice_date))
        labels = {'not_paid': ('Unpaid', 'bad'), 'partial': ('Partly paid', 'warn'), 'paid': ('Paid', 'good'),
                  'in_payment': ('Paid', 'good'), 'reversed': ('Reversed', 'mute')}
        tabs = [{'key': 'all', 'label': 'All', 'n': len(moves)},
                {'key': 'unpaid', 'label': 'Unpaid', 'n': len(moves.filtered(lambda m: m.payment_state == 'not_paid'))},
                {'key': 'partial', 'label': 'Partly paid', 'n': len(moves.filtered(lambda m: m.payment_state == 'partial'))},
                {'key': 'paid', 'label': 'Paid', 'n': len(moves.filtered(lambda m: m.payment_state in ('paid', 'in_payment')))}]
        if state == 'unpaid':
            moves = moves.filtered(lambda m: m.payment_state == 'not_paid')
        elif state == 'partial':
            moves = moves.filtered(lambda m: m.payment_state == 'partial')
        elif state == 'paid':
            moves = moves.filtered(lambda m: m.payment_state in ('paid', 'in_payment'))
        if search:
            moves = moves.filtered(lambda m: search.lower() in (m.name or '').lower())
        rows = []
        for m in moves:
            label, tone = labels.get(m.payment_state, (m.payment_state, 'mute'))
            suffix = ('?as=%s' % preview) if preview else ''
            rows.append([
                cell(m.name, bold=True, href='/dealer/invoices/%s%s' % (m.id, suffix)),
                cell(m.invoice_date.strftime('%d %b %Y') if m.invoice_date else ''),
                cell(m.invoice_date_due.strftime('%d %b %Y') if m.invoice_date_due else ''),
                cell(money(m.amount_total), align='end'), cell(money(m.amount_total - m.amount_residual), align='end'),
                cell(money(m.amount_residual), align='end', tone='bad' if m.amount_residual else None),
                cell(label, tone=tone),
                cell('Download PDF', tone='info', href='/dealer/invoices/%s/pdf%s' % (m.id, suffix)),
            ])
        return self._table(
            dealer, 'invoices', preview, flt, '/dealer/invoices', 'Invoice from Kumbayah Foods', 'What you owe the company.',
            ['Invoice', 'Date', 'Due', 'Amount', 'Paid', 'Outstanding', 'Status', ''], rows,
            tabs=tabs, active=state, search=search,
            summary=[('Total outstanding', money(sum(moves.mapped('amount_residual'))))], empty='No invoice in this period.')

    def _own_invoice(self, move_id, preview):
        dealer, bounce = self._gate(preview)
        if bounce:
            return None, None, bounce
        move = request.env['account.move'].sudo().browse(move_id).exists()
        if (not move or move.move_type != 'out_invoice' or move.state != 'posted'
                or move.partner_id.commercial_partner_id.id != dealer.id):
            return dealer, None, request.redirect('/dealer/invoices' + ('?as=%s' % preview if preview else ''))
        return dealer, move, None

    @http.route('/dealer/invoices/<int:move_id>', type='http', auth='public', website=True, sitemap=False)
    def invoice_page(self, move_id, **kw):
        preview = kw.get('as')
        dealer, move, bounce = self._own_invoice(move_id, preview)
        if bounce:
            return bounce
        payments = []
        try:
            for part in move._get_all_reconciled_invoice_partials():
                counterpart = part.get('aml')
                payments.append({'date': counterpart.date, 'ref': counterpart.move_id.name, 'amount': part.get('amount')})
        except Exception:  # noqa: BLE001 - the page does not depend on it
            payments = []
        return request.render('l4e_dealer_hub.hub_invoice', self._ctx(
            dealer, 'invoices', preview, move=move, payments=payments, money=money, qty=qty,
            lines=move.invoice_line_ids.filtered(lambda l: l.display_type == 'product')))

    @http.route('/dealer/invoices/<int:move_id>/pdf', type='http', auth='public', website=True, sitemap=False)
    def invoice_pdf(self, move_id, **kw):
        """The invoice as Odoo prints it."""
        preview = kw.get('as')
        dealer, move, bounce = self._own_invoice(move_id, preview)
        if bounce:
            return bounce
        pdf, _kind = request.env['ir.actions.report'].sudo()._render_qweb_pdf('account.account_invoices', move.ids)
        name = '%s.pdf' % (move.name or 'Invoice').replace('/', '-')
        return request.make_response(pdf, headers=[
            ('Content-Type', 'application/pdf'), ('Content-Length', len(pdf)),
            ('Content-Disposition', 'attachment; filename="%s"' % name)])

    @http.route('/dealer/collections', type='http', auth='public', website=True, sitemap=False)
    def collections_page(self, state='all', search=None, **kw):
        preview = kw.get('as')
        dealer, bounce = self._gate(preview)
        if bounce:
            return bounce
        flt = Filter(dict(kw, state=state if state != 'all' else None, search=search))
        invoices = request.env['ff.outlet.invoice'].sudo().search(
            [('distributor_id', '=', dealer.id), ('cancelled', '=', False)], limit=800).filtered(lambda i: flt.has(i.date))
        labels = {'open': ('Open', 'bad'), 'partial': ('Part paid', 'warn'), 'paid': ('Paid', 'good')}
        tabs = [{'key': 'all', 'label': 'All', 'n': len(invoices)}] + [
            {'key': k, 'label': v[0], 'n': len(invoices.filtered(lambda i, k=k: i.state == k))}
            for k, v in labels.items()]
        if state != 'all':
            invoices = invoices.filtered(lambda i: i.state == state)
        if search:
            invoices = invoices.filtered(lambda i: search.lower() in (i.name + i.partner_id.name).lower())
        rows = []
        for i in invoices:
            label, tone = labels.get(i.state, (i.state, 'mute'))
            rows.append([
                cell(i.partner_id.display_name, bold=True), cell(i.name),
                cell(i.date.strftime('%d %b %Y') if i.date else ''),
                cell(i.due_date.strftime('%d %b %Y') if i.due_date else '', tone='bad' if i.overdue else None),
                cell(money(i.amount_total), align='end'), cell(money(i.amount_confirmed), align='end'),
                cell(money(i.amount_awaiting), align='end'),
                cell(money(i.amount_pending), align='end', tone='bad' if i.amount_pending else None),
                cell(label, tone=tone),
            ])
        return self._table(
            dealer, 'collections', preview, flt, '/dealer/collections', 'Payment Collection',
            'What the outlets owe you, and what the field has collected and handed over.',
            ['Outlet', 'Invoice', 'Date', 'Due', 'Billed', 'Confirmed', 'Awaiting', 'Pending', 'Status'], rows,
            tabs=tabs, active=state, search=search,
            summary=[('Billed', money(sum(invoices.mapped('amount_total')))),
                     ('Collected & confirmed', money(sum(invoices.mapped('amount_confirmed')))),
                     ('Awaiting confirmation', money(sum(invoices.mapped('amount_awaiting')))),
                     ('Still to collect', money(sum(invoices.mapped('amount_pending'))))],
            empty='No outlet invoice yet. They are raised when you record a delivery.')

    @http.route('/dealer/handovers', type='http', auth='public', website=True, sitemap=False)
    def handovers_page(self, state='all', search=None, **kw):
        """Money the field handed to this distributor: who gave it, who took it, from which outlets."""
        preview = kw.get('as')
        dealer, bounce = self._gate(preview)
        if bounce:
            return bounce
        flt = Filter(dict(kw, state=state if state != 'all' else None, search=search))
        records = request.env['ff.distributor.handover'].sudo().search(
            [('distributor_id', '=', dealer.id)], limit=800).filtered(lambda h: flt.has(h.date))
        labels = {'handed': ('Awaiting confirmation', 'warn'), 'confirmed': ('Confirmed', 'good'),
                  'rejected': ('Rejected', 'bad')}
        tabs = [{'key': 'all', 'label': 'All', 'n': len(records)}] + [
            {'key': k, 'label': v[0], 'n': len(records.filtered(lambda h, k=k: h.state == k))}
            for k, v in labels.items()]
        if state != 'all':
            records = records.filtered(lambda h: h.state == state)
        if search:
            term = search.lower()
            records = records.filtered(lambda h: term in ' '.join([
                h.name or '', h.employee_id.name or '', h.received_by or '', h.reference or '',
                ' '.join(h._ff_outlets().mapped('name'))]).lower())
        rows = []
        for h in records:
            label, tone = labels.get(h.state, (h.state, 'mute'))
            link = '/dealer/handovers/%s%s' % (h.id, ('?as=%s' % preview) if preview else '')
            outlets = h._ff_outlets()
            rows.append([
                cell(h.name, bold=True, href=link),
                cell(h.date.strftime('%d %b %Y') if h.date else ''),
                cell(h.employee_id.name or ''),
                cell(h.received_by or '-'),
                cell(', '.join(outlets.mapped('name')[:3]) + (' +%d' % (len(outlets) - 3) if len(outlets) > 3 else '')),
                cell(h.mode_id.name or '-'), cell(h.reference or '-'),
                cell(money(h.amount), align='end', bold=True), cell(label, tone=tone),
            ])
        total = sum(records.filtered(lambda h: h.state != 'rejected').mapped('amount'))
        return self._table(
            dealer, 'handovers', preview, flt, '/dealer/handovers', 'Money Received',
            'Outlet money the field team handed to you. Open one to see which outlets it came from.',
            ['Handover', 'Date', 'Handed by', 'Received by', 'Outlets', 'Mode', 'Reference', 'Amount', 'Status'], rows,
            tabs=tabs, active=state, search=search,
            summary=[('Received', money(total)),
                     ('Confirmed', money(sum(records.filtered(lambda h: h.state == 'confirmed').mapped('amount')))),
                     ('Awaiting confirmation', money(sum(records.filtered(lambda h: h.state == 'handed').mapped('amount'))))],
            empty='No money has been handed to you in this period.')

    @http.route('/dealer/handovers/<int:handover_id>', type='http', auth='public', website=True, sitemap=False)
    def handover_page(self, handover_id, **kw):
        preview = kw.get('as')
        dealer, bounce = self._gate(preview)
        if bounce:
            return bounce
        record = request.env['ff.distributor.handover'].sudo().browse(handover_id).exists()
        if not record or record.distributor_id != dealer:
            return request.redirect('/dealer/handovers' + ('?as=%s' % preview if preview else ''))
        parts = record.line_ids or request.env['ff.distributor.handover.line']
        rows = [{'outlet': l.partner_id.display_name, 'payment': l.payment_id.name,
                 'collected': l.payment_id.date, 'mode': l.payment_id.mode_id.name,
                 'invoices': ', '.join(l.payment_id.line_ids.mapped('invoice_id.name')),
                 'amount': l.amount} for l in parts]
        if not rows:  # older handovers gave whole payments
            rows = [{'outlet': p.partner_id.display_name, 'payment': p.name, 'collected': p.date,
                     'mode': p.mode_id.name, 'invoices': ', '.join(p.line_ids.mapped('invoice_id.name')),
                     'amount': p.amount} for p in record.payment_ids]
        return request.render('l4e_dealer_hub.hub_handover', self._ctx(
            dealer, 'handovers', preview, h=record, rows=rows, money=money,
            states={'handed': 'Awaiting confirmation', 'confirmed': 'Confirmed', 'rejected': 'Rejected'}))

    @http.route('/dealer/returns', type='http', auth='public', website=True, sitemap=False)
    def returns_page(self, state='all', search=None, **kw):
        preview = kw.get('as')
        dealer, bounce = self._gate(preview)
        if bounce:
            return bounce
        flt = Filter(dict(kw, state=state if state != 'all' else None, search=search))
        rows, tabs = [], []
        if 'ff.distributor.note' in request.env:
            tones = {'pending': 'warn', 'approved': 'good', 'rejected': 'bad'}
            Note = request.env['ff.distributor.note']
            notes = Note.sudo().search([('distributor_id', '=', dealer.id)], limit=800).filtered(lambda n: flt.has(n.date))
            tabs = [{'key': 'all', 'label': 'All', 'n': len(notes)},
                    {'key': 'debit', 'label': 'Debit notes', 'n': len(notes.filtered(lambda n: n.kind == 'debit'))},
                    {'key': 'credit', 'label': 'Credit notes', 'n': len(notes.filtered(lambda n: n.kind == 'credit'))}]
            if state in ('debit', 'credit'):
                notes = notes.filtered(lambda n: n.kind == state)
            if search:
                term = search.lower()
                notes = notes.filtered(lambda n: term in ((n.name or '') + (n.partner_id.name or '') + (n.reason or '')
                                                          + (n.demand_id.name or '')).lower())
            kinds, sources = dict(Note._fields['kind'].selection), dict(Note._fields['source'].selection)
            states = dict(Note._fields['state'].selection)
            for n in notes:
                link = '/dealer/returns/%s%s' % (n.id, ('?as=%s' % preview) if preview else '')
                rows.append([
                    cell(n.name, bold=True, href=link), cell(n.date.strftime('%d %b %Y') if n.date else ''),
                    cell(kinds.get(n.kind, n.kind), tone='warn' if n.kind == 'debit' else 'info'),
                    cell(sources.get(n.source, '')), cell(n.partner_id.display_name or '-'),
                    cell(n.employee_id.name or ''), cell(n.demand_id.name or ''),
                    cell(qty(n.quantity_total), align='center'), cell(money(n.amount), align='end'),
                    cell(states.get(n.state, n.state), tone=tones.get(n.state)),
                ])
        return self._table(
            dealer, 'returns', preview, flt, '/dealer/returns', 'Debit/Credit Notes to Kumbayah Foods',
            'Debit and credit notes between you and the company: free goods, samples, damaged stock and margin. Open one for the full details.',
            ['Reference', 'Date', 'Type', 'Raised for', 'Outlet', 'Raised by', 'Demand', 'Units', 'Value', 'Status'], rows,
            tabs=tabs, active=state, search=search, empty='Nothing raised in this period.')

    @http.route('/dealer/returns/<int:note_id>', type='http', auth='public', website=True, sitemap=False)
    def note_page(self, note_id, **kw):
        preview = kw.get('as')
        dealer, bounce = self._gate(preview)
        if bounce:
            return bounce
        note = request.env['ff.distributor.note'].sudo().browse(note_id).exists()
        if not note or note.distributor_id != dealer:
            return request.redirect('/dealer/returns' + ('?as=%s' % preview if preview else ''))
        return request.render('l4e_dealer_hub.hub_note', self._ctx(
            dealer, 'returns', preview, note=note, money=money, qty=qty,
            sources=dict(note._fields['source'].selection), kinds=dict(note._fields['kind'].selection),
            states=dict(note._fields['state'].selection)))

    @http.route('/dealer/foc', type='http', auth='public', website=True, sitemap=False)
    def foc_page(self, **kw):
        preview = kw.get('as')
        dealer, bounce = self._gate(preview)
        if bounce:
            return bounce
        flt = Filter(kw)
        Line = request.env['ff.demand.line']
        lines = Line.sudo().search([('distributor_id', '=', dealer.id), ('is_foc', '=', True)], order='id desc',
                                   limit=600).filtered(lambda l: flt.has(l.date)) if 'is_foc' in Line._fields else Line
        rows = []
        for l in lines:
            rows.append([
                cell(l.date.strftime('%d %b %Y') if l.date else ''), cell(l.partner_id.display_name, bold=True),
                cell(l.product_id.display_name), cell(l.demand_id.name),
                cell(qty(l.quantity), align='center'), cell(qty(l.approved_quantity), align='center'),
                cell(qty(l.delivered_quantity), align='center'),
                cell(l.demand_id.delivery_status_id.name or dict(l.demand_id._fields['state'].selection).get(l.state, ''),
                     tone='info'),
            ])
        return self._table(
            dealer, 'foc', preview, flt, '/dealer/foc', 'Samples',
            'Free goods given to the outlets, covered by our debit note to you.',
            ['Date', 'Outlet', 'Product', 'Demand', 'Free qty', 'Approved', 'Delivered', 'Status'], rows,
            empty='No free goods in this period.')

    # ------------------------------------------------------------------
    # Stock
    # ------------------------------------------------------------------
    def _stock_table(self, dealer, flt, search=None):
        """Per product: what it started the period with, what came in and went out, what is left."""
        Move = request.env['l4e.dealer.stock.move'].sudo()
        per = {}
        for m in Move.search([('distributor_id', '=', dealer.id)]):
            row = per.setdefault(m.product_id, {'open': 0.0, 'in': 0.0, 'out': 0.0})
            if flt.start_dt and m.date < flt.start_dt:
                row['open'] += m.signed_qty
            elif not flt.end_dt or m.date < flt.end_dt:
                row['in' if m.direction == 'in' else 'out'] += m.quantity
        rows, total_value, total_units = [], 0.0, 0.0
        for product, r in sorted(per.items(), key=lambda kv: kv[0].display_name or ''):
            if search and search.lower() not in (product.display_name or '').lower():
                continue
            closing = r['open'] + r['in'] - r['out']
            price = product.ff_distributor_price() if hasattr(product, 'ff_distributor_price') else product.list_price
            total_value += closing * price
            total_units += closing
            rows.append([
                cell(product.display_name, bold=True), cell(product.default_code or ''), cell(product.uom_id.name or ''),
                cell(qty(r['open']), align='center'), cell(qty(r['in']), align='center', tone='good' if r['in'] else None),
                cell(qty(r['out']), align='center', tone='warn' if r['out'] else None),
                cell(qty(closing), align='center', tone='bad' if closing <= 0 else None, bold=True),
                cell(money(closing * price), align='end'),
            ])
        columns = ['Product', 'Code', 'Unit', 'Opening', 'In', 'Out', 'Closing', 'Value (at PTS)']
        return columns, rows, total_units, total_value

    @http.route('/dealer/stock', type='http', auth='public', website=True, sitemap=False)
    def stock_page(self, search=None, **kw):
        preview = kw.get('as')
        dealer, bounce = self._gate(preview)
        if bounce:
            return bounce
        flt = Filter(dict(kw, search=search), default='month')
        columns, rows, units, value = self._stock_table(dealer, flt, search)
        main_tabs = [
            {'label': 'My Stock', 'href': flt.link('/dealer/stock'), 'on': True},
            {'label': 'Stock In / Out', 'href': flt.link('/dealer/stock/moves'), 'on': False},
        ]
        return self._table(
            dealer, 'stock', preview, flt, '/dealer/stock', 'Stock',
            'Opening, stock in, stock out and what is left, for the period you choose.',
            columns, rows, search=search,
            summary=[('Units on hand', qty(units)), ('Stock value (PTS)', money(value))]
            + ([('Stock count saved', '%s product(s) updated' % kw['saved'])] if kw.get('saved') else []),
            empty='No stock recorded yet. Add your opening stock to begin.',
            export='/dealer/stock/export',
            action=[('Update current stock', flt.link('/dealer/stock/count'))],
            main_tabs=main_tabs)

    @http.route('/dealer/stock/moves', type='http', auth='public', website=True, sitemap=False)
    def moves_page(self, state='all', search=None, **kw):
        preview = kw.get('as')
        dealer, bounce = self._gate(preview)
        if bounce:
            return bounce
        flt = Filter(dict(kw, state=state if state != 'all' else None, search=search), default='month')
        columns, rows, tabs = self._moves(dealer, flt, state, search)
        main_tabs = [
            {'label': 'My Stock', 'href': flt.link('/dealer/stock'), 'on': False},
            {'label': 'Stock In / Out', 'href': flt.link('/dealer/stock/moves'), 'on': True},
        ]
        return self._table(
            dealer, 'stock', preview, flt, '/dealer/stock/moves', 'Stock',
            'Every transfer in and out of your stock: shipments from us, deliveries to outlets, returns and adjustments.',
            columns, rows, tabs=tabs, active=state, search=search, empty='No stock movement in this period.',
            export='/dealer/stock/export?kind=moves',
            action=[('Add stock entry', flt.link('/dealer/stock/add'), 'fa-plus')],
            main_tabs=main_tabs)

    def _moves(self, dealer, flt, state='all', search=None):
        Move = request.env['l4e.dealer.stock.move'].sudo()
        moves = Move.search([('distributor_id', '=', dealer.id)], limit=1500).filtered(lambda m: flt.has(m.date))
        tabs = [{'key': 'all', 'label': 'All', 'n': len(moves)},
                {'key': 'in', 'label': 'Stock in', 'n': len(moves.filtered(lambda m: m.direction == 'in'))},
                {'key': 'out', 'label': 'Stock out', 'n': len(moves.filtered(lambda m: m.direction == 'out'))}]
        if state in ('in', 'out'):
            moves = moves.filtered(lambda m: m.direction == state)
        if search:
            term = search.lower()
            moves = moves.filtered(lambda m: term in ((m.product_id.display_name or '') + (m.reference or '')
                                                      + (m.partner_id.name or '')).lower())
        kinds = dict(Move._fields['kind'].selection)
        rows = []
        for m in moves:
            # Match mockup pill tones:
            # - Delivered to Outlet: tone 'delivery' (yellow/orange)
            # - Adjustment (+): tone 'adjust-pos' (green)
            # - Adjustment (-): tone 'adjust-neg' (peach/tan)
            # - Other in: tone 'good', other out: tone 'warn'
            if m.kind == 'delivery':
                type_tone = 'delivery'
            elif m.kind == 'adjust_in':
                type_tone = 'adjust-pos'
            elif m.kind == 'adjust_out':
                type_tone = 'adjust-neg'
            elif m.direction == 'in':
                type_tone = 'good'
            else:
                type_tone = 'warn'

            qty_str = ('+' if m.direction == 'in' else '-') + qty(m.quantity) + ' ' + (m.uom_id.name or '')
            rows.append([
                cell(m.date.strftime('%d %b %Y %H:%M') if m.date else ''),
                cell((m.product_id.display_name or '').upper(), bold=True),
                cell(kinds.get(m.kind, m.kind), tone=type_tone),
                cell(m.partner_id.name or ''),
                cell(m.reference or ''),
                cell(qty_str, align='center', tone='qty-pos' if m.direction == 'in' else 'qty-neg'),
            ])
        return ['DATE', 'PRODUCT', 'TYPE', 'OUTLET', 'REFERENCE', 'QUANTITY'], rows, tabs

    @http.route('/dealer/stock/add', type='http', auth='public', website=True, sitemap=False)
    def stock_add(self, **kw):
        preview = kw.get('as')
        dealer, bounce = self._gate(preview)
        if bounce:
            return bounce
        flt = Filter(kw, default='month')
        products = request.env['product.product'].sudo().search([('sale_ok', '=', True)], order='name', limit=800)
        kinds = [(k, v) for k, v in request.env['l4e.dealer.stock.move']._fields['kind'].selection if k != 'delivery']
        return request.render('l4e_dealer_hub.hub_stock_add', self._ctx(
            dealer, 'stock', preview, flt=flt, path='/dealer/stock', products=products, kinds=kinds, steps={p.id: step(p) for p in products},
            error=kw.get('error'), saved=kw.get('saved')))

    def _countable(self):
        """The products a distributor can hold: whatever the field sells."""
        Product = request.env['product.product'].sudo()
        domain = [('sale_ok', '=', True)]
        return Product.search(domain, order='name', limit=800)

    @http.route('/dealer/stock/count', type='http', auth='public', website=True, sitemap=False)
    def stock_count(self, search=None, **kw):
        """Today's real quantities: type what is on the shelf and the difference is booked for you."""
        preview = kw.get('as')
        dealer, bounce = self._gate(preview)
        if bounce:
            return bounce
        flt = Filter(kw, default='month')
        on_hand = request.env['l4e.dealer.stock.move'].ff_on_hand(dealer)
        products = self._countable()
        if search:
            products = products.filtered(lambda p: search.lower() in (p.display_name or '').lower())
        rows = [{'product': p, 'system': on_hand.get(p.id, 0.0), 'step': step(p)} for p in products]
        return request.render('l4e_dealer_hub.hub_stock_count', self._ctx(
            dealer, 'stock', preview, flt=flt, path='/dealer/stock', rows=rows, search=search, qty=qty,
            saved=kw.get('saved'), error=kw.get('error')))

    @http.route('/dealer/stock/count/save', type='http', auth='public', website=True, methods=['POST'], sitemap=False)
    def stock_count_save(self, **post):
        preview = post.get('as')
        dealer, bounce = self._gate(preview)
        if bounce:
            return bounce
        Move = request.env['l4e.dealer.stock.move'].sudo()
        on_hand = Move.ff_on_hand(dealer)
        today = date.today().isoformat()
        changed = 0
        description = (post.get('description') or '').strip()
        for key, value in post.items():
            if not key.startswith('cnt_') or value in (None, ''):
                continue
            try:
                product = request.env['product.product'].sudo().browse(int(key[4:])).exists()
                counted = float(value)
            except ValueError:
                continue
            if not product or counted < 0:
                continue
            rounding = product.uom_id.rounding or 0.01
            counted = round(counted / rounding) * rounding
            diff = round(counted - on_hand.get(product.id, 0.0), 6)
            if abs(diff) < rounding / 2:
                continue
            ref = description or ('Stock count %s' % today)
            Move.create({
                'distributor_id': dealer.id, 'product_id': product.id,
                'kind': 'adjust_in' if diff > 0 else 'adjust_out', 'quantity': abs(diff),
                'reference': ref, 'note': description or ('Counted %s' % qty(counted)),
                'entered_by': request.env.user.name, 'company_id': dealer.company_id.id or request.env.company.id,
            })
            changed += 1
        suffix = ('?as=%s&' % preview) if preview else '?'
        return request.redirect('/dealer/stock%ssaved=%s' % (suffix, changed))

    @http.route('/dealer/stock/save', type='http', auth='public', website=True, methods=['POST'], sitemap=False)
    def stock_save(self, **post):
        preview = post.get('as')
        dealer, bounce = self._gate(preview)
        if bounce:
            return bounce
        Move = request.env['l4e.dealer.stock.move'].sudo()
        back = '/dealer/stock/add?' + urlencode({'as': preview} if preview else {})
        sep = '&' if preview else ''
        kind = post.get('kind')
        if not kind or kind not in dict(Move._fields['kind'].selection) or kind == 'delivery':
            return request.redirect(back + sep + 'error=Invalid+stock+entry+type.')

        description = (post.get('description') or '').strip()
        if not description:
            return request.redirect(back + sep + 'error=Description+is+required.')

        reference = (post.get('reference') or '').strip() or description
        on_hand = Move.ff_on_hand(dealer)

        # Parse quantities entered for each flavour
        created_count = 0
        for key, value in post.items():
            if not key.startswith('qty_') or value in (None, ''):
                continue
            try:
                product = request.env['product.product'].sudo().browse(int(key[4:])).exists()
                amount = float(value)
            except (ValueError, TypeError):
                continue
            if not product or amount <= 0:
                continue

            # Check on hand if negative/return
            if kind in ('return', 'adjust_out') and amount > on_hand.get(product.id, 0.0) + 0.0001:
                return request.redirect(back + sep + 'error=You+only+have+%s+of+%s.' % (
                    qty(on_hand.get(product.id, 0.0)), product.name))

            Move.create({
                'distributor_id': dealer.id,
                'product_id': product.id,
                'kind': kind,
                'quantity': amount,
                'reference': reference,
                'note': description,
                'entered_by': request.env.user.name,
                'company_id': dealer.company_id.id or request.env.company.id,
            })
            created_count += 1

        if created_count == 0:
            return request.redirect(back + sep + 'error=Please+enter+a+quantity+greater+than+0+for+at+least+one+product.')

        return request.redirect('/dealer/stock/moves' + ('?as=%s' % preview if preview else ''))

    @http.route('/dealer/stock/export', type='http', auth='public', website=True, sitemap=False)
    def stock_export(self, kind='stock', search=None, **kw):
        preview = kw.get('as')
        dealer, bounce = self._gate(preview)
        if bounce:
            return bounce
        import xlsxwriter
        flt = Filter(dict(kw, search=search), default='month')
        if kind == 'moves':
            columns, rows, _tabs = self._moves(dealer, flt, kw.get('state', 'all'), search)
            title = 'Stock In-Out'
        else:
            columns, rows, _u, _v = self._stock_table(dealer, flt, search)
            title = 'Stock'
        buffer = io.BytesIO()
        book = xlsxwriter.Workbook(buffer, {'in_memory': True})
        sheet = book.add_worksheet(title[:30])
        head = book.add_format({'bold': True, 'bg_color': '#1E3A8A', 'font_color': '#FFFFFF', 'border': 1})
        plain = book.add_format({'border': 1})
        sheet.write(0, 0, '%s - %s' % (dealer.name, title), book.add_format({'bold': True, 'font_size': 14}))
        sheet.write(1, 0, 'Period: %s' % flt.label)
        for c, name in enumerate(columns):
            sheet.write(3, c, name, head)
            sheet.set_column(c, c, 22 if c == 0 else 15)
        for r, row in enumerate(rows, start=4):
            for c, item in enumerate(row):
                sheet.write(r, c, item['t'], plain)
        book.close()
        name = '%s %s.xlsx' % (title, date.today().isoformat())
        return request.make_response(buffer.getvalue(), headers=[
            ('Content-Type', 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'),
            ('Content-Disposition', 'attachment; filename="%s"' % name)])
