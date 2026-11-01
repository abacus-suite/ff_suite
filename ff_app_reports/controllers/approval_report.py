"""Manager Mode > Reports > Approval Report: what the manager's team asked for, and how each request ended.

``GET /api/v1/approvals/report?start&end`` answers ``{counts, items}``; ``POST /api/v1/approvals/report/export``
prepares an Excel or PDF file of the same list and gives a short-lived link to it.
"""
import io
import time as clock
from html import escape

from odoo import fields, http
from odoo.http import request

from odoo.addons.ff_mobile_api.controllers.clients import to_int
from odoo.addons.ff_mobile_api.controllers.common import ApiError, api_route, body, ok, ref

from .reports import LINK_SECONDS, _sign, _unsign

KIND_LABELS = {
    'beats': 'New Beat', 'contacts': 'New Outlet', 'notes': 'Debit / Credit Note', 'returns': 'Return',
    'leaves': 'Leave', 'regularisation': 'Attendance Fix', 'expenses': 'Expense', 'allowances': 'TA',
    'da': 'DA', 'access': 'Contact Access',
}
STATE_LABELS = {'approved': 'Approved', 'rejected': 'Rejected', 'pending': 'Pending'}
LEAVE_STATES = {'validate': 'approved', 'refuse': 'rejected'}
KIND_MODELS = {
    'beats': 'ff.beat', 'contacts': 'res.partner', 'leaves': 'hr.leave', 'regularisation': 'ff.regularisation',
    'expenses': 'ff.expense.claim', 'allowances': 'ff.allowance.claim', 'da': 'ff.da.claim',
    'returns': 'ff.return', 'access': 'ff.contact.access.request',
}
RETURN_STATES = {'approved': 'approved', 'credited': 'approved', 'rejected': 'rejected'}


def _day(value):
    """A date or datetime as a date; None when empty."""
    if not value:
        return None
    return value.date() if hasattr(value, 'date') else value


def _money(record, amount):
    symbol = record.currency_id.symbol if 'currency_id' in record._fields and record.currency_id else ''
    return '%s%.2f' % (symbol or '', amount or 0.0)


def _row(kind, rec_id, title, employee, detail, day, state, reason=None):
    return {
        'id': rec_id, 'kind': kind, 'kind_label': KIND_LABELS[kind], 'title': title,
        'employee': ref(employee), 'detail': detail or None,
        'date': day.isoformat() if day else None, 'state': state, 'reason': reason or None,
    }


def collect(employee, start, end):
    """Every request of the manager's team dated within the period, newest first."""
    env = request.env
    team = employee._ff_subordinates()
    if not team:
        return []
    rows = []

    def inside(day):
        return bool(day) and start <= day <= end

    def source(model, build):
        """One kind of request; a module that is not installed, or one that fails, never spoils the others."""
        if model not in env:
            return
        try:
            with env.cr.savepoint():
                rows.extend(r for r in build() if r)
        except Exception:  # noqa: BLE001
            return

    def beats():
        for b in env['ff.beat'].sudo().search([('ff_created_by_employee_id', 'in', team.ids)]):
            day = _day(b.write_date or b.create_date)
            if inside(day):
                yield _row('beats', b.id, 'New Beat · %s' % (b.code or b.name), b.ff_created_by_employee_id,
                           '%d outlets' % len(b.line_ids), day, b.ff_approval_state if b.ff_approval_state in STATE_LABELS else 'pending')

    def contacts():
        for p in env['res.partner'].sudo().search([
                ('ff_is_client', '=', True), ('ff_created_by_employee_id', 'in', team.ids)]):
            day = _day(p.create_date)
            if inside(day) and p.ff_approval_state:
                yield _row('contacts', p.id, 'New Outlet · %s' % p.name, p.ff_created_by_employee_id,
                           p.city or None, day,
                           p.ff_approval_state if p.ff_approval_state in STATE_LABELS else 'pending')

    def leaves():
        for lv in env['hr.leave'].sudo().search([
                ('employee_id', 'in', team.ids), ('request_date_from', '>=', start), ('request_date_from', '<=', end)]):
            days = lv.number_of_days
            yield _row('leaves', lv.id, 'Leave · %g days' % days, lv.employee_id,
                       lv.holiday_status_id.name, lv.request_date_from, LEAVE_STATES.get(lv.state, 'pending'))

    def regularisation():
        for r in env['ff.regularisation'].sudo().search([
                ('employee_id', 'in', team.ids), ('date', '>=', start), ('date', '<=', end), ('state', '!=', 'draft')]):
            yield _row('regularisation', r.id, 'Attendance Fix', r.employee_id, r.note or dict(
                r._fields['reason'].selection).get(r.reason), r.date,
                       r.state if r.state in STATE_LABELS else 'pending')

    def expenses():
        for c in env['ff.expense.claim'].sudo().search([
                ('employee_id', 'in', team.ids), ('date', '>=', start), ('date', '<=', end), ('state', '!=', 'draft')]):
            yield _row('expenses', c.id, 'Expense · %s' % _money(c, c.amount), c.employee_id,
                       c.category_id.name, c.date, c.state if c.state in STATE_LABELS else 'pending')

    def allowances():
        for c in env['ff.allowance.claim'].sudo().search([
                ('employee_id', 'in', team.ids), ('date', '>=', start), ('date', '<=', end), ('state', '!=', 'draft')]):
            yield _row('allowances', c.id, 'TA · %s' % _money(c, c.amount), c.employee_id, c.note,
                       c.date, c.state if c.state in STATE_LABELS else 'pending')

    def da():
        for c in env['ff.da.claim'].sudo().search([
                ('employee_id', 'in', team.ids), ('date', '>=', start), ('date', '<=', end), ('state', '!=', 'draft')]):
            yield _row('da', c.id, 'DA · %s' % _money(c, c.amount), c.employee_id, c.detail,
                       c.date, c.state if c.state in STATE_LABELS else 'pending')

    def returns():
        for r in env['ff.return'].sudo().search([('employee_id', 'in', team.ids)]):
            day = _day(r.date)
            if inside(day):
                yield _row('returns', r.id, 'Return · %s' % (r.name or ''), r.employee_id, r.note, day,
                           RETURN_STATES.get(r.state, 'pending'))

    def access():
        for r in env['ff.contact.access.request'].sudo().search([
                ('employee_id', 'in', team.ids), ('date_from', '>=', start), ('date_from', '<=', end)]):
            yield _row('access', r.id, 'Contact Access', r.employee_id, r.reason, r.date_from,
                       r.state if r.state in STATE_LABELS else 'pending',
                       reason=r.decision_note if r.state == 'rejected' else None)

    for model, build in (('ff.beat', beats), ('res.partner', contacts), ('hr.leave', leaves),
                         ('ff.regularisation', regularisation), ('ff.expense.claim', expenses),
                         ('ff.allowance.claim', allowances), ('ff.da.claim', da), ('ff.return', returns),
                         ('ff.contact.access.request', access)):
        source(model, build)
    _add_reasons(rows)
    rows.sort(key=lambda r: (r['date'] or '', r['id']), reverse=True)
    return rows


def _add_reasons(rows):
    """The reason a manager gave on each rejected request (kept when it was rejected in the app)."""
    Reason = request.env['ff.reject.reason'] if 'ff.reject.reason' in request.env else None
    for kind, model in KIND_MODELS.items():
        rejected = [r for r in rows if r['kind'] == kind and r['state'] == 'rejected']
        if not rejected:
            continue
        found = Reason.ff_reasons(model, [r['id'] for r in rejected]) if Reason is not None else {}
        for r in rejected:
            r['reason'] = found.get(r['id']) or r['reason']


def counts_of(rows):
    out = {'received': len(rows), 'approved': 0, 'rejected': 0, 'pending': 0}
    for r in rows:
        out[r['state']] += 1
    return out


def _period(start, end):
    low, high = fields.Date.to_date(start), fields.Date.to_date(end)
    if not low or not high or high < low:
        raise ApiError('Choose the start and the end of the period.')
    if (high - low).days > 366:
        raise ApiError('Choose a period of one year or less.')
    return low, high


def _filtered(rows, state=None, kind=None, employee_id=None):
    if state in STATE_LABELS:
        rows = [r for r in rows if r['state'] == state]
    if kind:
        rows = [r for r in rows if r['kind'] == kind]
    if employee_id:
        rows = [r for r in rows if (r['employee'] or {}).get('id') == employee_id]
    return rows


def _xlsx(rows, low, high):
    import xlsxwriter
    stream = io.BytesIO()
    book = xlsxwriter.Workbook(stream, {'in_memory': True})
    sheet = book.add_worksheet('Approval Report')
    head = book.add_format({'bold': True, 'bg_color': '#0F4C5C', 'font_color': '#FFFFFF', 'border': 1})
    cell = book.add_format({'border': 1})
    sheet.write(0, 0, 'Approval Report %s to %s' % (low, high), book.add_format({'bold': True, 'font_size': 13}))
    for col, title in enumerate(('Date', 'Type', 'Request', 'Employee', 'Details', 'Status', 'Reason')):
        sheet.write(2, col, title, head)
        sheet.set_column(col, col, 16 if col in (0, 5) else 28)
    for i, r in enumerate(rows, start=3):
        values = (r['date'] or '', r['kind_label'], r['title'], (r['employee'] or {}).get('name') or '',
                  r['detail'] or '', STATE_LABELS[r['state']], r['reason'] or '')
        for col, value in enumerate(values):
            sheet.write(i, col, value, cell)
    book.close()
    return stream.getvalue()


def _html(rows, low, high):
    def td(v):
        return '<td style="border:1px solid #999;padding:4px 8px">%s</td>' % escape(str(v or ''))
    head = ''.join('<th style="border:1px solid #999;padding:4px 8px;background:#0F4C5C;color:#fff">%s</th>' % h
                   for h in ('Date', 'Type', 'Request', 'Employee', 'Details', 'Status', 'Reason'))
    body_rows = ''.join('<tr>%s</tr>' % ''.join(td(v) for v in (
        r['date'], r['kind_label'], r['title'], (r['employee'] or {}).get('name'), r['detail'],
        STATE_LABELS[r['state']], r['reason'])) for r in rows)
    return ('<html><head><meta charset="utf-8"/></head><body style="font-family:Arial;font-size:11px">'
            '<h2>Approval Report</h2><div>%s to %s</div><br/>'
            '<table style="border-collapse:collapse;width:100%%"><tr>%s</tr>%s</table></body></html>'
            % (low, high, head, body_rows))


class FieldForceApprovalReportApi(http.Controller):

    @api_route('/api/v1/approvals/report', methods=('GET',), manager=True)
    def report(self, employee, start=None, end=None, **kw):
        low, high = _period(start, end)
        rows = collect(employee, low, high)
        return ok({'counts': counts_of(rows), 'items': rows})

    @api_route('/api/v1/approvals/report/export', methods=('POST',), manager=True)
    def export(self, employee, **kw):
        data = body()
        low, high = _period(data.get('start'), data.get('end'))
        kind = 'pdf' if data.get('format') == 'pdf' else 'excel'
        token = _sign({
            'e': employee.id, 'ar': kind, 's': low.isoformat(), 'n': high.isoformat(),
            'st': data.get('state') or '', 'kd': data.get('kind') or '', 'em': to_int(data.get('employee_id')) or 0,
            'x': int(clock.time()) + LINK_SECONDS})
        return ok({'path': '/api/v1/approvals/report/download?t=%s' % token, 'expires_in': LINK_SECONDS})

    @http.route('/api/v1/approvals/report/download', type='http', auth='public', methods=['GET'], csrf=False,
                save_session=False)
    def download(self, t=None, **kw):
        payload = _unsign(t)
        if not payload or not payload.get('ar'):
            return request.make_response('This download link has expired. Export again from the app.',
                                         headers=[('Content-Type', 'text/plain; charset=utf-8')], status=410)
        employee = request.env['hr.employee'].sudo().browse(payload['e']).exists()
        if not employee:
            return request.not_found()
        low, high = fields.Date.to_date(payload['s']), fields.Date.to_date(payload['n'])
        rows = _filtered(collect(employee, low, high), payload.get('st'), payload.get('kd') or None,
                         payload.get('em') or None)
        name = 'Approval_Report_%s_%s' % (low.isoformat(), high.isoformat())
        if payload['ar'] == 'pdf':
            try:
                content = request.env['ir.actions.report'].sudo()._run_wkhtmltopdf([_html(rows, low, high)])
            except Exception as error:  # noqa: BLE001 - the server may have no PDF engine
                return request.make_response('A PDF cannot be made on this server (%s).' % error, status=400,
                                             headers=[('Content-Type', 'text/plain; charset=utf-8')])
            mime, filename = 'application/pdf', name + '.pdf'
        else:
            content = _xlsx(rows, low, high)
            mime, filename = 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet', name + '.xlsx'
        return request.make_response(content, headers=[
            ('Content-Type', mime), ('Content-Disposition', 'attachment; filename="%s"' % filename),
            ('Content-Length', str(len(content)))])
