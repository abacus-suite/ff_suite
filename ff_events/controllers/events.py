"""Events: create with opening stock, stock for the next day, end of day, end of event, report and Excel."""
import io
import time as clock
from collections import Counter

from odoo import fields, http
from odoo.http import request

from odoo.addons.ff_app_reports.controllers.reports import LINK_SECONDS, _sign, _unsign
from odoo.addons.ff_mobile_api.controllers.common import ApiError, api_route, body, ok, ref

EPS = 0.0001


def _num(value):
    try:
        return max(float(value or 0), 0.0)
    except (TypeError, ValueError):
        return 0.0


def _mrp(env, template, distributors=None):
    """A distributor's own MRP when one has it, else the product's."""
    if 'distributor.mrp.line' in env and distributors:
        line = env['distributor.mrp.line'].sudo().search(
            [('partner_id', 'in', distributors.ids), ('product_id', '=', template.id)], limit=1)
        if line and line.mrp:
            return line.mrp
    return template.ff_mrp if 'ff_mrp' in template._fields else template.list_price


def _mrp_map(env, distributors):
    """``{(distributor id, template id): mrp}`` in a single query."""
    if 'distributor.mrp.line' not in env or not distributors:
        return {}
    lines = env['distributor.mrp.line'].sudo().search([('partner_id', 'in', distributors.ids)])
    return {(l.partner_id.id, l.product_id.id): l.mrp for l in lines if l.mrp}


def _mrp_from(table, template, distributors):
    for partner in distributors:
        value = table.get((partner.id, template.id))
        if value:
            return value
    return template.ff_mrp if 'ff_mrp' in template._fields else template.list_price


def event_mrp(event, template):
    """The MRP of a flavour in the event's price category (the product's own when there is none)."""
    line = event.price_category_id.line_ids.filtered(lambda l: l.product_id == template)[:1]
    if line:
        return line.mrp
    return template.ff_mrp if 'ff_mrp' in template._fields else template.list_price


def _code(template):
    return getattr(template, 'ff_sku_code', False) or template.default_code or template.name


# --------------------------------------------------------------------------- the stock arithmetic
def _day_rows(event, day):
    """What each flavour starts ``day`` with and what was added: ``{product: (opening, added)}``.

    The first day starts with the stock the event was opened with. After that the day starts with what
    stayed from the day before, and anything a distributor sent since is *added*. If the stock was
    returned, the day starts from the stock entered again, so that is its opening.
    """
    earlier = event.day_ids.filtered(lambda d: d.date < day).sorted('date')
    previous = earlier[-1] if earlier else None
    since = previous.date if previous else None
    new = {}
    for line in event.stock_ids:
        if line.date <= day and (since is None or line.date > since):
            new[line.product_id.id] = new.get(line.product_id.id, 0.0) + line.qty
    rows = {}
    if previous is None or previous.closing_action == 'return':
        for pid, qty in new.items():
            rows[pid] = (qty, 0.0)
        return rows
    carried = {l.product_id.id: l.closing for l in previous.line_ids}
    for pid in set(carried) | set(new):
        rows[pid] = (carried.get(pid, 0.0), new.get(pid, 0.0))
    return rows


def _day_number(event, day):
    return len(event.day_ids.filtered(lambda d: d.date < day)) + 1


def _event_data(event, detail=False):
    env = request.env
    today = event.env['hr.employee'].browse(event.employee_id.id)._ff_today()
    data = {
        'id': event.id, 'name': event.name, 'state': event.state,
        'has_offer': event.has_offer, 'offer_price': int(event.offer_price or 0),
        'mrp': event.mrp,
        'price_category': ref(event.price_category_id) if event.price_category_id else None,
        'completed': event.state == 'done',
        'final_saved': bool(event.day_ids.filtered('is_final')),
        'cash_total': round(sum(event.day_ids.mapped('cash_received')), 2),
        'coupons_total': sum(event.day_ids.mapped('coupons_used')),
        'date_start': event.date_start.isoformat() if event.date_start else None,
        'date_end': event.date_end.isoformat() if event.date_end else None,
        'location': event.location or '',
        'district': ref(event.district_id) if event.district_id else None,
        'territory': ref(event.territory_id) if event.territory_id else None,
        'staff': [ref(s) for s in event.staff_ids], 'created_by': ref(event.employee_id),
        'coupons_used': event.coupons_used, 'days': len(event.day_ids),
        'day_no': _day_number(event, today),
        'latitude': event.latitude, 'longitude': event.longitude,
        'geofence_m': _geofence_m(),
    }
    if detail == 'card':
        previous = event.day_ids.filtered(lambda d: d.date < today)
        data.update({
            'has_previous_day': bool(previous),
            'day_dates': [d.date.isoformat() for d in event.day_ids],
        })
    elif detail:
        distributors = event.stock_ids.mapped('distributor_id')
        table = _mrp_map(env, distributors)
        rows = _day_rows(event, today)
        previous = event.day_ids.filtered(lambda d: d.date < today).sorted('date')
        returned_yesterday = bool(previous and previous[-1].closing_action == 'return')
        todays_stock = event.stock_ids.filtered(lambda s: not previous or s.date > previous[-1].date)
        data.update({
            'products': [{'id': t.id, 'name': t.name, 'code': _code(t), 'mrp': event_mrp(event, t)}
                         for t in sorted({s.product_id for s in event.stock_ids} |
                                         {env['product.template'].browse(p) for p in rows},
                                         key=lambda t: getattr(t, 'ff_sku_code', False) or t.default_code or t.name)],
            'opening': [{'product_id': pid, 'opening': o, 'added': a} for pid, (o, a) in rows.items()],
            'returned_yesterday': returned_yesterday,
            'has_previous_day': bool(previous),
            # A day that is on hold needs its opening stock confirmed before the day can be ended.
            'needs_opening': event.state == 'on_hold' and bool(previous) and
            not event.stock_ids.filtered(lambda s: s.date == today) and returned_yesterday,
            'stock': [{'distributor': ref(s.distributor_id), 'product_id': s.product_id.id, 'qty': s.qty,
                       'date': s.date.isoformat()} for s in todays_stock],
            'day_dates': [d.date.isoformat() for d in event.day_ids],
            # How the last closed day ended, for the Start Day page.
            'last_day': (lambda d: {
                'date': d.date.isoformat(), 'closing_action': d.closing_action,
                'returned': sum(d.line_ids.mapped('returned')), 'closing': sum(d.line_ids.mapped('closing')),
                'coupons': d.coupons_used, 'cash': d.cash_received,
            } if d else None)(event.day_ids.sorted('date')[-1:] or None),
            # Only the distributors this event took stock from can have it returned.
            'distributors': [ref(d) for d in event.stock_ids.mapped('distributor_id')],
        })
    return data


def _geofence_m():
    """The distance to the event the person must be within; 0 when the office does not ask."""
    task = request.env['ff.task.type'].sudo().search([('code', '=', 'events')], limit=1)
    if not task:
        return 200
    return (task.geofence_radius or 200) if task.geofence_required else 0


def _mine(employee, event_id):
    event = request.env['ff.event'].sudo().browse(event_id).exists()
    team = employee | employee._ff_subordinates()
    if not event or (event.employee_id not in team and employee not in event.staff_ids):
        raise ApiError('Event not found.', 404, 'not_found')
    return event


# --------------------------------------------------------------------------- report
def _report(event, day=None):
    env = request.env
    days = event.day_ids.sorted('date')
    chosen = days.filtered(lambda d: d.date.isoformat() == day) if day else days
    distributors = event.stock_ids.mapped('distributor_id')
    rows = {}
    previous_closing = {}
    order = list(days)
    for entry in order:
        index = order.index(entry)
        before = order[index - 1] if index else None
        prev_close = {l.product_id.id: l.closing for l in before.line_ids} if before else {}
        for line in entry.line_ids:
            if entry not in chosen:
                continue
            pid = line.product_id.id
            # Stock that arrived mid-event is "added" - including stock entered again after a return.
            fresh = line.added + (line.opening - prev_close.get(pid, 0.0) if before else 0.0)
            if day:
                fresh = line.added
            row = rows.setdefault(pid, {
                'product': ref(line.product_id), 'code': _code(line.product_id),
                'mrp': _mrp(env, line.product_id, distributors),
                'opening': line.opening, 'added': 0.0, 'samples': 0.0, 'damage': 0.0, 'returned': 0.0,
                'closing': 0.0, 'sold': 0.0})
            row['added'] += fresh
            row['samples'] += line.samples
            row['damage'] += line.damage
            row['returned'] += line.returned
            row['closing'] = line.closing
            row['sold'] += line.sold
    out = sorted(rows.values(), key=lambda r: r['code'])
    keys = ('opening', 'added', 'samples', 'damage', 'returned', 'closing', 'sold')
    totals = {k: sum(r[k] for r in out) for k in keys}
    del previous_closing
    return {
        'event': _event_data(event), 'day': day,
        'days': [d.date.isoformat() for d in days],
        'rows': out, 'totals': totals,
        'coupons': {'used': event.coupons_used, 'value': int(event.offer_price or 0),
                    'amount': event.coupons_used * int(event.offer_price or 0)},
    }


def _xlsx(event):
    import xlsxwriter
    stream = io.BytesIO()
    book = xlsxwriter.Workbook(stream, {'in_memory': True})
    head = book.add_format({'bold': True, 'bg_color': '#0F4C5C', 'font_color': 'white', 'border': 1})
    cell = book.add_format({'border': 1})
    bold = book.add_format({'bold': True, 'border': 1})
    title = book.add_format({'bold': True, 'font_size': 14})
    green = book.add_format({'bold': True, 'border': 1, 'font_color': '#15803D'})

    def table(sheet, row, titles, data, total=None):
        for col, text in enumerate(titles):
            sheet.write(row, col, text, head)
        for r in data:
            row += 1
            for col, value in enumerate(r):
                sheet.write(row, col, value, cell)
        if total:
            row += 1
            for col, value in enumerate(total):
                sheet.write(row, col, value, bold)
        return row + 2

    cols = ['Flavour', 'Code', 'Opening', 'Added', 'Samples', 'Damage', 'Returned', 'Closing', 'Sales']
    # ---- summary of the whole event
    summary = book.add_worksheet('Summary')
    summary.write(0, 0, event.name, title)
    info = [('Location', event.location or ''), ('Territory', event.territory_id.name or ''),
            ('District', event.district_id.name or ''), ('MRP', event.mrp),
            ('Offer', ('Rs. %s coupon' % event.offer_price) if event.has_offer else 'No'),
            ('Conducted by', ', '.join(event.staff_ids.mapped('name'))),
            ('Status', dict(event._fields['state'].selection).get(event.state)),
            ('From', str(event.date_start or '')), ('To', str(event.date_end or '')),
            ('Coupons used', event.coupons_used)]
    for i, (k, v) in enumerate(info, start=2):
        summary.write(i, 0, k, bold)
        summary.write(i, 1, v, cell)
    full = _report(event)
    row = len(info) + 4
    summary.write(row - 1, 0, 'All days', title)
    row = table(summary, row, cols, [
        [r['product']['name'], r['code'], r['opening'], r['added'], r['samples'], r['damage'], r['returned'],
         r['closing'], r['sold']] for r in full['rows']],
        ['Total', '', *[full['totals'][k] for k in ('opening', 'added', 'samples', 'damage', 'returned', 'closing', 'sold')]])
    summary.write(row, 0, 'Sales = Opening + Added - Samples - Damage - Returned - Closing', cell)
    row += 2
    summary.write(row, 0, 'Sales by day', title)
    days = event.day_ids.sorted('date')
    products = sorted({l.product_id for d in days for l in d.line_ids}, key=lambda t: _code(t))
    matrix = []
    for t in products:
        sold = []
        for d in days:
            line = d.line_ids.filtered(lambda l, t=t: l.product_id == t)
            sold.append(sum(line.mapped('sold')))
        matrix.append([t.name, _code(t), *sold, sum(sold)])
    table(summary, row + 1, ['Flavour', 'Code', *['Day %s (%s)' % (i + 1, d.date) for i, d in enumerate(days)], 'Total'],
          matrix)
    summary.set_column(0, 0, 28)
    summary.set_column(1, 12, 13)

    # ---- opening stock by distributor
    sheet = book.add_worksheet('Stock from distributors')
    data = [[s.date.isoformat(), s.distributor_id.name, s.product_id.name, _code(s.product_id), s.qty]
            for s in event.stock_ids.sorted('date')]
    table(sheet, 0, ['Date', 'Distributor', 'Flavour', 'Code', 'Bottles'], data,
          ['Total', '', '', '', sum(event.stock_ids.mapped('qty'))])
    sheet.set_column(0, 4, 22)

    # ---- one sheet per day: opening, closing, next day opening, samples, damage, returned and sales
    days_list = list(days)
    for i, d in enumerate(days_list):
        sheet = book.add_worksheet('Day %s' % (i + 1))
        sheet.write(0, 0, '%s - Day %s - %s' % (event.name, i + 1, d.date), title)
        nxt = days_list[i + 1] if i + 1 < len(days_list) else None
        next_open = {l.product_id.id: l.opening for l in nxt.line_ids} if nxt else {}
        lines = d.line_ids.sorted(lambda l: _code(l.product_id))
        data = [[l.product_id.name, _code(l.product_id), l.opening, l.added, l.samples, l.damage, l.returned,
                 l.closing, next_open.get(l.product_id.id, 0.0) if nxt else '', l.sold] for l in lines]
        sums = [sum(lines.mapped(f)) for f in ('opening', 'added', 'samples', 'damage', 'returned', 'closing')]
        row = table(sheet, 2, ['Flavour', 'Code', 'Opening balance', 'Stock added', 'Samples', 'Damage',
                               'Returned', 'Closing (end of day)', 'Next day opening', 'Sales'],
                    data, ['Total', '', *sums, sum(next_open.values()) if nxt else '', sum(lines.mapped('sold'))])
        if d.return_ids:
            sheet.write(row, 0, 'Returned to distributors', title)
            table(sheet, row + 1, ['Distributor', 'Flavour', 'Code', 'Bottles'],
                  [[r.distributor_id.name, r.product_id.name, _code(r.product_id), r.qty] for r in d.return_ids])
        sheet.set_column(0, 9, 18)
    book.close()
    return stream.getvalue()


class FieldForceEventsApi(http.Controller):

    @api_route('/api/v1/events/options', methods=('GET',))
    def options(self, employee, **kw):
        env = request.env
        flavours = env['product.product'].sudo().ff_flavours()
        templates = flavours.mapped('product_tmpl_id').sorted(lambda t: getattr(t, 'ff_sku_code', False) or t.default_code or t.name)
        company_partner = employee.company_id.partner_id
        all_distributors = env['res.partner'].sudo().search(
            [('ff_category_type', '=', 'distributor'), ('active', '=', True)], limit=300, order='name')
        staff = employee | employee._ff_subordinates()
        districts = employee.ff_district_ids or env['ff.district'].sudo().search([], limit=200)
        territories = employee.ff_territory_ids or env['ff.territory'].sudo().search([], limit=300)
        beats = env['ff.beat'].sudo().search([('territory_id', 'in', territories.ids)])
        table = _mrp_map(env, all_distributors)
        territory_rows = []
        for t in territories.sorted('name'):
            partners = beats.filtered(lambda b, t=t: b.territory_id == t).line_ids.partner_id
            local = all_distributors & partners
            mrps = [_mrp_from(table, tpl, local) for tpl in templates]
            mrp = Counter(m for m in mrps if m).most_common(1)
            territory_rows.append(dict(
                ref(t), district_id=t.district_id.id or None, district=t.district_id.name or None,
                mrp=mrp[0][0] if mrp else 0,
                distributor_ids=local.ids))
        return ok({
            'products': [{'id': t.id, 'name': t.name, 'code': _code(t), 'mrp': _mrp_from(table, t, env['res.partner'])}
                         for t in templates],
            'distributors': [dict(ref(company_partner), company=True)] +
                            [ref(d) for d in all_distributors if d != company_partner],
            'company_id': company_partner.id,
            'districts': [ref(d) for d in districts],
            'territories': territory_rows,
            'price_categories': [{
                'id': c.id, 'name': c.name,
                'mrp': {str(l.product_id.id): l.mrp for l in c.line_ids}}
                for c in env['ff.event.price.category'].sudo().search([])],
            'staff': [ref(s) for s in staff.sorted('name')],
            'offers': [20, 30, 50],
        })

    @api_route('/api/v1/events', methods=('GET',))
    def listing(self, employee, active=None, **kw):
        team = employee | employee._ff_subordinates()
        domain = ['|', ('employee_id', 'in', team.ids), ('staff_ids', 'in', employee.ids)]
        if active:
            domain.append(('state', 'in', ('running', 'on_hold')))
        events = request.env['ff.event'].sudo().search(domain, limit=100)
        return ok({'events': [_event_data(e, detail='card' if active else False) for e in events]})

    @api_route('/api/v1/events', methods=('POST',))
    def create(self, employee, **kw):
        data = body()
        name = (data.get('name') or '').strip()
        if not name:
            raise ApiError('Give the event a name.', 400, 'invalid')
        has_offer = bool(data.get('has_offer', True))
        offer = str(int(data.get('offer_price') or 0)) if has_offer else False
        if has_offer and offer not in ('20', '30', '50'):
            raise ApiError('Choose the coupon value.', 400, 'invalid')
        category = request.env['ff.event.price.category'].sudo().browse(
            int(data.get('price_category_id') or 0)).exists()
        if not category:
            raise ApiError('Choose the price category.', 400, 'invalid')
        rows = [r for r in (data.get('stock') or []) if _num(r.get('qty')) > 0]
        if not rows:
            raise ApiError('Add the opening stock.', 400, 'invalid')
        staff = request.env['hr.employee'].sudo().browse([int(i) for i in (data.get('staff_ids') or [])]) or employee
        today = employee._ff_today()
        event = request.env['ff.event'].sudo().create({
            'name': name, 'employee_id': employee.id, 'staff_ids': [(6, 0, staff.ids)],
            'district_id': data.get('district_id') or False, 'territory_id': data.get('territory_id') or False,
            'location': data.get('location') or '', 'latitude': data.get('latitude') or 0.0,
            'longitude': data.get('longitude') or 0.0, 'price_category_id': category.id,
            'has_offer': has_offer, 'offer_price': offer,
            'state': 'running' if data.get('confirm') else 'draft', 'date_start': today,
            'stock_ids': [(0, 0, {'date': today, 'distributor_id': int(r['distributor_id']),
                                  'product_id': int(r['product_id']), 'qty': _num(r.get('qty'))}) for r in rows],
        })
        return ok(_event_data(event, detail=True), 201)

    @api_route('/api/v1/events/<int:event_id>', methods=('GET',))
    def detail(self, employee, event_id, **kw):
        return ok(_event_data(_mine(employee, event_id), detail=True))

    @api_route('/api/v1/events/<int:event_id>/stock', methods=('POST',))
    def stock(self, employee, event_id, **kw):
        """Step 2 and 3 of a later day: stock a distributor sent, or the stock entered again after a return."""
        event = _mine(employee, event_id)
        if event.state == 'done':
            raise ApiError('This event has ended.', 400, 'invalid')
        today = employee._ff_today()
        rows = [r for r in (body().get('stock') or []) if _num(r.get('qty')) > 0]
        event.stock_ids.filtered(lambda s: s.date == today).unlink()
        event.write({'state': 'running', 'stock_ids': [(0, 0, {
            'date': today, 'distributor_id': int(r['distributor_id']), 'product_id': int(r['product_id']),
            'qty': _num(r.get('qty'))}) for r in rows]})
        return ok(_event_data(event, detail=True))

    def _save_day(self, employee, event, final):
        data = body()
        if event.state == 'done':
            raise ApiError('This event has ended.', 400, 'invalid')
        day = employee._ff_today()
        opening = _day_rows(event, day)
        samples = {int(k): _num(v) for k, v in (data.get('samples') or {}).items()}
        damage = {int(k): _num(v) for k, v in (data.get('damage') or {}).items()}
        returns = [r for r in (data.get('returns') or []) if _num(r.get('qty')) > 0]
        action = 'return' if (final or data.get('action') == 'return') else 'stays'
        if action == 'stays':
            returns = []
        sent_back = {}
        for r in returns:
            pid = int(r['product_id'])
            sent_back[pid] = sent_back.get(pid, 0.0) + _num(r['qty'])
        if action == 'return' and not returns and any(o + a for o, a in opening.values()):
            raise ApiError('Choose the distributor the stock goes back to.', 400, 'invalid')
        # What stays at the event is counted by staff (closing). Sales is what the app finds missing:
        # opening + added - samples - damage - returned - closing. When the stock goes back, closing is 0.
        counted = {int(k): _num(v) for k, v in (data.get('closing') or {}).items()}
        Template = request.env['product.template'].sudo()
        lines = []
        for pid, (o, a) in opening.items():
            available = o + a
            closing = 0.0 if action == 'return' else counted.get(pid, 0.0)
            accounted = samples.get(pid, 0.0) + damage.get(pid, 0.0) + sent_back.get(pid, 0.0) + closing
            name = Template.browse(pid).name
            if accounted > available + EPS:
                raise ApiError('%s: samples, damage, returned and closing (%g) are more than the stock (%g).'
                               % (name, accounted, available), 400, 'invalid')
            lines.append((0, 0, {
                'product_id': pid, 'opening': o, 'added': a, 'samples': samples.get(pid, 0.0),
                'damage': damage.get(pid, 0.0), 'returned': sent_back.get(pid, 0.0), 'closing': closing}))
        coupons = data.get('coupons_used')
        cash = data.get('cash_received')
        if event.has_offer and coupons in (None, ''):
            raise ApiError('Enter the coupons used today.', 400, 'invalid')
        if cash in (None, ''):
            raise ApiError('Enter the cash received today.', 400, 'invalid')
        Day = request.env['ff.event.day'].sudo()
        entry = Day.search([('event_id', '=', event.id), ('date', '=', day)], limit=1)
        if final:
            pass
        if entry:
            entry.line_ids.unlink()
            entry.return_ids.unlink()
        else:
            entry = Day.create({'event_id': event.id, 'date': day})
        entry.write({
            'is_final': final, 'closing_action': action, 'line_ids': lines,
            'coupons_used': int(coupons or 0), 'cash_received': _num(cash),
            'return_ids': [(0, 0, {'distributor_id': int(r['distributor_id']), 'product_id': int(r['product_id']),
                                   'qty': _num(r['qty'])}) for r in returns],
        })
        if final:
            # The last day is saved; the event is completed on its own step, after the cash and coupons table.
            event.write({'coupons_used': sum(event.day_ids.mapped('coupons_used'))})
        else:
            event.write({'state': 'on_hold', 'coupons_used': sum(event.day_ids.mapped('coupons_used'))})
        result = _event_data(event, detail=True)
        result['closing_total'] = sum(l[2]['closing'] for l in lines)
        return ok(result)

    @api_route('/api/v1/events/<int:event_id>/day', methods=('POST',))
    def end_of_day(self, employee, event_id, **kw):
        return self._save_day(employee, _mine(employee, event_id), final=False)

    @api_route('/api/v1/events/<int:event_id>/end', methods=('POST',))
    def end_of_event(self, employee, event_id, **kw):
        return self._save_day(employee, _mine(employee, event_id), final=True)

    @api_route('/api/v1/events/<int:event_id>/report', methods=('GET',))
    def report(self, employee, event_id, day=None, **kw):
        return ok(_report(_mine(employee, event_id), day))

    @api_route('/api/v1/events/<int:event_id>/export', methods=('POST',))
    def export(self, employee, event_id, **kw):
        event = _mine(employee, event_id)
        token = _sign({'e': employee.id, 'ev': event.id, 'x': int(clock.time()) + LINK_SECONDS})
        return ok({'path': '/api/v1/events/download?t=%s' % token, 'expires_in': LINK_SECONDS})

    @http.route('/api/v1/events/download', type='http', auth='public', methods=['GET'], csrf=False,
                save_session=False)
    def download(self, t=None, **kw):
        payload = _unsign(t)
        if not payload or 'ev' not in payload:
            return request.make_response('This download link has expired. Export again from the app.',
                                         headers=[('Content-Type', 'text/plain; charset=utf-8')], status=410)
        event = request.env['ff.event'].sudo().browse(payload['ev']).exists()
        if not event:
            return request.not_found()
        content = _xlsx(event)
        filename = 'Event_%s.xlsx' % event.name.replace(' ', '_')
        return request.make_response(content, headers=[
            ('Content-Type', 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'),
            ('Content-Disposition', 'attachment; filename="%s"' % filename),
            ('Content-Length', str(len(content))),
        ])
