"""Manager mode: My Team, the Team Beat Plan detail and the Employee report (with Excel)."""
import io
import time as clock
from odoo import fields, http
from odoo.http import request

from odoo.addons.ff_base.tools import to_iso

from .clients import client_domain
from .common import ApiError, api_route, ok, ref


def _dates(employee, start, end):
    today = employee._ff_today()
    try:
        low = fields.Date.to_date(start) if start else today.replace(day=1)
        high = fields.Date.to_date(end) if end else today
    except ValueError:
        raise ApiError('Dates must be YYYY-MM-DD.')
    if high < low:
        low, high = high, low
    return low, high


def _member(employee, member_id):
    """Someone in the manager's team, or the manager."""
    person = request.env['hr.employee'].sudo().browse(int(member_id)).exists()
    allowed = employee | employee._ff_subordinates()
    if not person or person not in allowed:
        raise ApiError('That person is not in your team.', 403, 'forbidden')
    return person


def _bottles(env, person, low, high):
    if 'ff.field.target' in env:
        return env['ff.field.target'].sudo().ff_actual(person, low, high)
    return {'bottles': 0, 'outlets': 0}


def _overdue(env, viewer, today):
    """Outlet and distributor overdue money for what the viewer can see."""
    if 'account.move' not in env:
        return {'total': 0.0, 'outlet': 0.0, 'distributor': 0.0}
    partners = env['res.partner'].sudo().search(client_domain(viewer))
    families = partners.mapped('commercial_partner_id')
    if not families:
        return {'total': 0.0, 'outlet': 0.0, 'distributor': 0.0}
    moves = env['account.move'].sudo().search([
        ('move_type', '=', 'out_invoice'), ('state', '=', 'posted'),
        ('payment_state', 'in', ('not_paid', 'partial')), ('invoice_date_due', '<', today),
        ('partner_id', 'child_of', families.ids), ('company_id', '=', viewer.company_id.id)])
    out = {'total': 0.0, 'outlet': 0.0, 'distributor': 0.0}
    for move in moves:
        kind = 'distributor' if getattr(move.partner_id.commercial_partner_id, 'ff_category_type', '') == 'distributor' \
            else 'outlet'
        out[kind] += move.amount_residual
        out['total'] += move.amount_residual
    return {k: round(v, 2) for k, v in out.items()}


def _report_data(env, employee, person, low, high):
    """Everything the Employee report shows for one person between two dates."""
    start = employee._ff_day_bounds(low)[0]
    end = employee._ff_day_bounds(high)[1]
    sudo = lambda model: env[model].sudo() if model in env else None  # noqa: E731

    # ---- attendance: days worked, late days, hours, distance
    days, late_days, hours, km = {}, {}, 0.0, 0.0
    if 'hr.attendance' in env:
        for att in env['hr.attendance'].sudo().search([
                ('employee_id', '=', person.id), ('check_in', '>=', start), ('check_in', '<', end)], order='check_in'):
            day = att.check_in.date().isoformat()
            row = days.setdefault(day, {'date': day, 'in_at': to_iso(att.check_in), 'out_at': None,
                                        'hours': 0.0, 'late': False, 'km': 0.0,
                                        'place': getattr(att, 'ff_in_address', None) or None})
            row['hours'] = round(row['hours'] + (att.worked_hours or 0.0), 2)
            row['out_at'] = to_iso(att.check_out) if att.check_out else row['out_at']
            row['km'] = round(row['km'] + (getattr(att, 'ff_odometer_km', 0.0) or 0.0), 1)
            late_min = getattr(att, 'ff_late_minutes', 0)
            shift = getattr(att, 'ff_shift_id', None) or getattr(att.employee_id, 'ff_shift_id', None)
            if not late_min and shift and att.check_in and att.employee_id:
                local_in = att.employee_id._ff_to_local(att.check_in)
                shift_hours, shift_mins = divmod(shift._ff_start_minutes(), 60)
                start_dt = local_in.replace(hour=shift_hours, minute=shift_mins, second=0, microsecond=0)
                late_min = max(0, int((local_in - start_dt).total_seconds() // 60))
            is_late = getattr(att, 'ff_day_status', '') == 'late' or (late_min > shift.grace_minutes if shift else late_min > 0)
            if is_late:
                row['late'] = True
                row['late_minutes'] = late_min
                late_days[day] = row
            hours += att.worked_hours or 0.0
            km += getattr(att, 'ff_odometer_km', 0.0) or 0.0

    # ---- beats and territories worked in the period
    lines = sudo('ff.route.plan.customer')
    planned_lines = lines.search([('day_id.employee_id', '=', person.id), ('day_id.date', '>=', low),
                                  ('day_id.date', '<=', high), ('selected', '=', True)]) if lines is not None \
        else env['res.partner']
    beats = planned_lines.mapped('day_id.beat_id') if planned_lines else env['ff.beat']
    territories = beats.mapped('territory_id') if beats and 'territory_id' in beats._fields else []
    visits_done = len(planned_lines.filtered(lambda l: l.visit_id)) if planned_lines else 0
    visit_rows = []
    for line in planned_lines.sorted(lambda l: (l.day_id.date, l.id)):
        v_type = (line.visit_id.visit_type or 'onsite').capitalize() if line.visit_id else ''
        visit_rows.append({'date': line.day_id.date.isoformat(), 'outlet': ref(line.partner_id),
                           'beat': line.day_id.beat_id.name or None, 'done': bool(line.visit_id),
                           'type': v_type, 'visit_type': v_type.lower() if v_type else None})

    # ---- tasks
    task_total = task_done = 0
    task_rows = []
    if 'ff.task' in env:
        tasks = env['ff.task'].sudo().search([
            ('employee_id', '=', person.id), ('date_deadline', '>=', low), ('date_deadline', '<=', high)])
        task_total = len(tasks)
        task_done = len(tasks.filtered(lambda t: t.state == 'done'))
        task_rows = [{'name': t.name, 'due': t.date_deadline.isoformat() if t.date_deadline else None,
                      'state': t.state,
                      'type': 'Onsite' if (t.visit_id and t.visit_id.visit_type == 'onsite') else 'Offsite',
                      'visit_type': t.visit_id.visit_type if (t.visit_id and t.visit_id.visit_type) else 'offsite'}
                     for t in tasks]

    # ---- sales and onboarding
    actual = _bottles(env, person, low, high)
    pos = 0
    if 'ff.demand' in env:
        pos = env['ff.demand'].sudo().search_count([
            ('employee_id', '=', person.id), ('date', '>=', start), ('date', '<', end), ('state', '!=', 'cancelled'),
            ('partner_id.ff_category_type', '=', 'distributor')])
    leads = env['res.partner'].sudo().with_context(active_test=False).search_count([
        ('ff_created_by_employee_id', '=', person.id), ('ff_category_type', '=', 'lead'),
        ('create_date', '>=', start), ('create_date', '<', end)])
    expenses = 0.0
    if 'ff.expense.claim' in env:
        claims = env['ff.expense.claim'].sudo().search([
            ('employee_id', '=', person.id), ('date', '>=', low), ('date', '<=', high), ('state', '!=', 'rejected')]) \
            if 'date' in env['ff.expense.claim']._fields else env['ff.expense.claim']
        expenses = round(sum(claims.mapped('amount')), 2)

    return {
        'employee': dict(ref(person), job=person.job_title or person.ff_designation_id.name or None),
        'from': low.isoformat(), 'to': high.isoformat(),
        'currency': employee.company_id.currency_id.name,
        'territories': [t.name for t in territories],
        'routes': [b.name for b in beats],
        'days_worked': len(days), 'late_days': len(late_days),
        'distance_km': round(km, 1), 'hours': round(hours, 2),
        'visits': {'done': visits_done, 'planned': len(planned_lines)},
        'tasks': {'done': task_done, 'total': task_total},
        'bottles': actual['bottles'], 'outlets': actual['outlets'],
        'pos_to_distributor': pos, 'new_leads': leads, 'expenses': expenses,
        'details': {
            'days': sorted(days.values(), key=lambda r: r['date']),
            'late': sorted(late_days.values(), key=lambda r: r['date']),
            'visits': visit_rows, 'tasks': task_rows,
            'routes': [{'name': b.name, 'territory': b.territory_id.name if 'territory_id' in b._fields else None}
                       for b in beats],
        },
    }


def _report_xlsx(data):
    import xlsxwriter
    stream = io.BytesIO()
    book = xlsxwriter.Workbook(stream, {'in_memory': True})
    head = book.add_format({'bold': True, 'bg_color': '#1A56DB', 'font_color': 'white', 'border': 1})
    cell = book.add_format({'border': 1})
    bold = book.add_format({'bold': True, 'border': 1})
    title = book.add_format({'bold': True, 'font_size': 14})
    sheet = book.add_worksheet('Employee report')
    sheet.write(0, 0, 'Employee report - %s' % data['employee']['name'], title)
    sheet.write(1, 0, '%s to %s' % (data['from'], data['to']))
    rows = [
        ('Territory', ', '.join(data['territories'])), ('Route', ', '.join(data['routes'])),
        ('Days worked', data['days_worked']), ('Late days', data['late_days']),
        ('Distance (km)', data['distance_km']), ('Hours', data['hours']),
        ('Visits (done / planned)', '%s / %s' % (data['visits']['done'], data['visits']['planned'])),
        ('Tasks (done / total)', '%s / %s' % (data['tasks']['done'], data['tasks']['total'])),
        ('Bottles sold', data['bottles']), ('Onboarded outlets', data['outlets']),
        ('POs to distributor', data['pos_to_distributor']), ('New leads', data['new_leads']),
        ('Expenses', data['expenses']),
    ]
    for i, (k, v) in enumerate(rows, start=3):
        sheet.write(i, 0, k, bold)
        sheet.write(i, 1, v, cell)
    sheet.set_column(0, 0, 28)
    sheet.set_column(1, 1, 36)

    def table(name, titles, data_rows):
        ws = book.add_worksheet(name)
        for c, t in enumerate(titles):
            ws.write(0, c, t, head)
        for r, values in enumerate(data_rows, start=1):
            for c, v in enumerate(values):
                ws.write(r, c, v, cell)
        ws.set_column(0, len(titles) - 1, 22)

    table('Days worked', ['Date', 'In', 'Out', 'Hours', 'Late', 'Km', 'Place'],
          [[d['date'], d['in_at'] or '', d['out_at'] or '', d['hours'], 'Yes' if d['late'] else '', d['km'],
            d['place'] or ''] for d in data['details']['days']])
    table('Visits', ['Date', 'Outlet', 'Beat', 'Visited', 'Type'],
          [[v['date'], v['outlet']['name'], v['beat'] or '', 'Yes' if v['done'] else 'No', v.get('type') or '']
           for v in data['details']['visits']])
    table('Tasks', ['Task', 'Due', 'Type', 'Status'],
          [[t['name'], t['due'] or '', t.get('type') or '', t['state']] for t in data['details']['tasks']])
    book.close()
    return stream.getvalue()


class FieldForceTeamManagerApi(http.Controller):

    @api_route('/api/v1/team/my', methods=('GET',), manager=True)
    def my_team(self, employee, start=None, end=None, root=None, **kw):
        """My Team: the team card and the people directly under ``root`` (me by default)."""
        env = request.env
        low, high = _dates(employee, start, end)
        top = _member(employee, root) if root and str(root) not in ('me', '0') else employee
        team = employee._ff_subordinates() if top == employee else top._ff_subordinates()
        direct = team.filtered(lambda p: p.parent_id == top)
        today = employee._ff_today()
        t_start, t_end = employee._ff_day_bounds(today)
        working = set()
        if 'hr.attendance' in env:
            working = {a.employee_id.id for a in env['hr.attendance'].sudo().search([
                ('employee_id', 'in', team.ids), ('check_in', '>=', t_start), ('check_in', '<', t_end),
                ('check_out', '=', False)])}
        start_dt, end_dt = employee._ff_day_bounds(low)[0], employee._ff_day_bounds(high)[1]
        visits = {}
        if 'ff.visit' in env:
            visits = {r[0].id: r[1] for r in env['ff.visit'].sudo()._read_group(
                [('employee_id', 'in', team.ids), ('check_in_at', '>=', start_dt), ('check_in_at', '<', end_dt)],
                ['employee_id'], ['__count'])}
        bottles = {p.id: _bottles(env, p, low, high)['bottles'] for p in team}

        def person_row(person):
            below = person._ff_subordinates()
            return {
                'id': person.id, 'name': person.name,
                'job': person.job_title or person.ff_designation_id.name or None,
                'working': person.id in working,
                'visits': visits.get(person.id, 0), 'bottles': bottles.get(person.id, 0),
                'team_count': len(below),
            }

        overdue = _overdue(env, employee, today)
        return ok({
            'from': low.isoformat(), 'to': high.isoformat(),
            'currency': employee.company_id.currency_id.name,
            'manager': dict(person_row(top), job=top.job_title or top.ff_designation_id.name or None),
            'team': len(team), 'working': len([p for p in team if p.id in working]),
            'visits': sum(visits.get(p.id, 0) for p in team),
            'bottles': sum(bottles.values()), 'overdue': overdue['total'],
            'people': [person_row(p) for p in direct.sorted('name')],
        })

    @api_route('/api/v1/team/beat-plan', methods=('GET',), manager=True)
    def beat_plan(self, employee, start=None, end=None, member=None, **kw):
        """Team Beat Plan: totals, each person's visits done and planned, and one person's outlets."""
        env = request.env
        low, high = _dates(employee, start, end)
        if not start and not end:
            low = high = employee._ff_today()
        team = employee._ff_subordinates()
        picked = _member(employee, member) if member and str(member) not in ('all', '0') else None
        scope = picked or team
        lines = env['ff.route.plan.customer'].sudo().search([
            ('day_id.employee_id', 'in', scope.ids), ('day_id.date', '>=', low), ('day_id.date', '<=', high),
            ('selected', '=', True)]) if 'ff.route.plan.customer' in env else env['res.partner']
        cancelled_of = lambda l: 'status' in l._fields and l.status == 'cancelled'  # noqa: E731

        def totals(rows):
            planned = len(rows)
            visited = len(rows.filtered(lambda l: l.status == 'visited' if 'status' in l._fields else l.visit_id)) if rows else 0
            cancelled = len([l for l in rows if cancelled_of(l)]) if rows else 0
            pending = max(planned - visited - cancelled, 0)
            return {'planned': planned, 'visited': visited, 'pending': pending, 'cancelled': cancelled}

        people = []
        for person in scope.sorted('name'):
            mine = lines.filtered(lambda l, p=person: l.day_id.employee_id == p)
            t = totals(mine)
            people.append(dict(t, employee=ref(person), job=person.job_title or None,
                               territory=', '.join(sorted({l.day_id.beat_id.name for l in mine if l.day_id.beat_id})) or None))
        outlets = []
        if picked:
            for line in lines.sorted(lambda l: (l.day_id.date, l.sequence if 'sequence' in l._fields else 0)):
                status = 'visited' if line.visit_id else ('cancelled' if cancelled_of(line) else 'pending')
                outlets.append({'outlet': ref(line.partner_id), 'status': status, 'date': line.day_id.date.isoformat(),
                                'visited_at': to_iso(line.visit_id.check_in_at) if line.visit_id else None})
        return ok({
            'from': low.isoformat(), 'to': high.isoformat(),
            'summary': totals(lines), 'people': people, 'outlets': outlets,
            'members': [ref(p) for p in team.sorted('name')],
        })

    @api_route('/api/v1/team/employee-report', methods=('GET',), manager=True)
    def employee_report(self, employee, member=None, start=None, end=None, **kw):
        low, high = _dates(employee, start, end)
        person = _member(employee, member) if member else employee
        return ok(_report_data(request.env, employee, person, low, high))

    @api_route('/api/v1/team/employee-report/export', methods=('POST',), manager=True)
    def employee_report_export(self, employee, **kw):
        try:
            from odoo.addons.ff_app_reports.controllers.reports import LINK_SECONDS, _sign
        except ImportError:
            raise ApiError('Downloads need the app reports module.', 400, 'invalid')
        from .common import body
        data = body()
        low, high = _dates(employee, data.get('start'), data.get('end'))
        person = _member(employee, data.get('member')) if data.get('member') else employee
        token = _sign({'e': employee.id, 'tm': person.id, 's': low.isoformat(), 'n': high.isoformat(),
                       'x': int(clock.time()) + LINK_SECONDS})
        return ok({'path': '/api/v1/team/employee-report/download?t=%s' % token, 'expires_in': LINK_SECONDS})

    @http.route('/api/v1/team/employee-report/download', type='http', auth='public', methods=['GET'],
                csrf=False, save_session=False)
    def employee_report_download(self, t=None, **kw):
        from odoo.addons.ff_app_reports.controllers.reports import _unsign
        payload = _unsign(t)
        if not payload or 'tm' not in payload:
            return request.make_response('This download link has expired. Export again from the app.',
                                         headers=[('Content-Type', 'text/plain; charset=utf-8')], status=410)
        env = request.env
        viewer = env['hr.employee'].sudo().browse(payload['e']).exists()
        person = env['hr.employee'].sudo().browse(payload['tm']).exists()
        if not viewer or not person:
            return request.not_found()
        data = _report_data(env, viewer, person, fields.Date.to_date(payload['s']), fields.Date.to_date(payload['n']))
        content = _report_xlsx(data)
        filename = 'Employee_report_%s_%s.xlsx' % (person.name.replace(' ', '_'), payload['s'])
        return request.make_response(content, headers=[
            ('Content-Type', 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'),
            ('Content-Disposition', 'attachment; filename="%s"' % filename),
            ('Content-Length', str(len(content))),
        ])
