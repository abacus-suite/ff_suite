from odoo import fields, http
from odoo.http import request

from odoo.addons.ff_base.tools import to_iso

from .clients import to_float, visible_client
from odoo.addons.ff_visits.models.ff_visit import PURPOSES, OffsiteConfirmation

from .common import (ApiError, api_route, body, check_device_clock, ok, ref,
                     require_punched_in, scope_members)
from .field_data import client_data, plan_data, visit_data


def _day(employee, value):
    try:
        return fields.Date.to_date(value) if value else employee._ff_today()
    except ValueError:
        raise ApiError('date must be YYYY-MM-DD.')


def _own_visit(employee, visit_id):
    visit = request.env['ff.visit'].sudo().browse(visit_id).exists()
    if not visit or visit.employee_id != employee:
        raise ApiError('Visit not found.', 404, 'not_found')
    return visit


def _require_details(partner):
    """With the setting on, an onboarded outlet or distributor with a required detail missing cannot be visited."""
    param = request.env['ir.config_parameter'].sudo().get_param('ff_base.ask_missing_details')
    if param not in ('True', 'true', '1'):
        return
    contact = partner.sudo()
    kind = getattr(contact, 'ff_category_type', None)
    if getattr(contact, 'ff_status', None) != 'onboarded' or kind not in ('outlet', 'distributor') \
            or not hasattr(contact, 'ff_onboard_missing'):
        return
    missing = contact.ff_onboard_missing(kind)
    if missing:
        raise ApiError('Details are missing for %s: %s. Fill them in to continue.' % (
            contact.name, ', '.join(missing)), 409, 'details_missing')


class FieldForceVisitsApi(http.Controller):

    @api_route('/api/v1/visits/check-in', methods=('POST',))
    def check_in(self, employee, **kw):
        data = body()
        try:
            partner_id = int(data.get('partner_id'))
        except (TypeError, ValueError):
            raise ApiError('partner_id is required.')
        partner = visible_client(employee, partner_id)
        _require_details(partner)
        check_device_clock(employee, data, 'check in')
        require_punched_in(employee, 'check in at a customer', data)
        try:
            visit = request.env['ff.visit'].ff_check_in(employee, partner, data)
        except OffsiteConfirmation as far:
            away = '%.1f km' % (far.distance / 1000.0) if far.distance >= 1000 else '%d m' % far.distance
            raise ApiError('%s is %s from where you are. Check in as an offsite visit?' % (far.client, away),
                           409, 'offsite_confirm')
        return ok(visit_data(visit))

    @api_route('/api/v1/visits/check-out', methods=('POST',))
    def check_out_open(self, employee, **kw):
        """Check out without knowing the visit id - a check-in queued offline has none yet.

        ``visit_uuid`` names the visit; without it the open visit is closed.
        """
        data = body()
        Visit = request.env['ff.visit'].sudo()
        visit = Visit.browse()
        if data.get('visit_uuid'):
            visit = Visit.search([('client_uuid', '=', data['visit_uuid']), ('employee_id', '=', employee.id)], limit=1)
        if not visit:
            visit = Visit.search([('employee_id', '=', employee.id), ('state', '=', 'ongoing')], limit=1)
        if not visit:
            raise ApiError('You are not checked in anywhere.', 404, 'not_found')
        return ok(visit_data(visit.ff_check_out(data)))

    @api_route('/api/v1/visits/<int:visit_id>/check-out', methods=('POST',))
    def check_out(self, employee, visit_id, **kw):
        return ok(visit_data(_own_visit(employee, visit_id).ff_check_out(body())))

    @api_route('/api/v1/visits/<int:visit_id>/purpose', methods=('POST',))
    def set_purpose(self, employee, visit_id, **kw):
        """Say what an open visit is for.

        A visit the app started on arrival was never asked, so it is asked on
        the customer's screen instead. Once answered it stands: the work the
        answer calls for is what the visit will be judged on.
        """
        visit = _own_visit(employee, visit_id)
        purpose = body().get('purpose')
        if purpose not in dict(PURPOSES):
            raise ApiError('Choose what this visit is for.')
        if visit.state != 'ongoing':
            raise ApiError('This visit is already closed.', 409, 'conflict')
        visit.sudo().write({'purpose': purpose})
        return ok(visit_data(visit))

    @api_route('/api/v1/visits/current', methods=('GET',))
    def current(self, employee, **kw):
        visit = request.env['ff.visit'].sudo().search(
            [('employee_id', '=', employee.id), ('state', '=', 'ongoing')], limit=1)
        return ok(visit_data(visit))

    @api_route('/api/v1/visits', methods=('GET',))
    def visits(self, employee, date=None, **kw):
        start, end = employee._ff_day_bounds(_day(employee, date))
        visits = request.env['ff.visit'].sudo().search([
            ('employee_id', '=', employee.id), ('check_in_at', '>=', start), ('check_in_at', '<', end),
        ])
        return ok([visit_data(v) for v in visits])

    @api_route('/api/v1/beat/today', methods=('GET',))
    def beat_today(self, employee, date=None, lat=None, lng=None, member=None, **kw):
        """The day's planned routes and customers (one or several routes).

        ``member`` looks at one person in the team's day instead of one's own,
        for a manager reading a plan rather than working it.
        """
        if member not in (None, '', 'me'):
            people, _label = scope_members(employee, member)
            employee = people[:1] or employee
        day = _day(employee, date)
        lat, lng = to_float(lat), to_float(lng)
        start, end = employee._ff_day_bounds(day)
        plans = request.env['ff.beat.plan'].sudo().search(
            [('employee_id', '=', employee.id), ('date', '=', day)], order='id')
        visits = request.env['ff.visit'].sudo().search([
            ('employee_id', '=', employee.id), ('check_in_at', '>=', start), ('check_in_at', '<', end),
        ], order='check_in_at asc')

        lines = plans.customer_line_ids.filtered('selected').sorted(lambda l: (l.day_id.id, l.sequence, l.id))
        rows = []
        for sequence, line in enumerate(lines, start=1):
            partner_visits = visits.filtered(lambda v, p=line.partner_id: v.partner_id == p)
            if partner_visits.filtered(lambda v: v.state == 'ongoing'):
                status = 'ongoing'
            elif partner_visits.filtered(lambda v: v.visit_type != 'offsite'):
                status = 'done'  # offsite visits are not counted as visited
            else:
                status = 'cancelled' if line.cancelled else 'pending'
            row = client_data(line.partner_id, lat, lng)
            row.update(sequence=sequence, visit_status=status, plan_status=line.status,
                       route=ref(line.beat_id),
                       visit=visit_data(partner_visits[-1:]) if partner_visits else None)
            rows.append(row)

        planned_partners = lines.partner_id
        planned_partner_ids = set(planned_partners.ids)
        ongoing = visits.filtered(lambda v: v.state == 'ongoing')[:1]
        # The tasks done today: unplanned completed tasks count as extra visits towards planned & visited
        tasks = []
        if 'ff.task.log' in request.env:
            low, high = employee._ff_day_bounds(day)
            for log in request.env['ff.task.log'].sudo().search([
                    ('employee_id', '=', employee.id), ('date', '>=', low), ('date', '<', high)], order='date asc'):
                is_onsite = bool(log.visit_id and log.visit_id.visit_type == 'onsite')
                # A task is planned if it is performed for a contact planned on today's beat
                is_planned = bool(log.partner_id and log.partner_id.id in planned_partner_ids)
                is_unplanned = not is_planned
                cat_type = getattr(log.partner_id, 'ff_category_type', '') or 'outlet' if log.partner_id else None
                tasks.append({
                    'id': log.id,
                    'time': to_iso(log.date),
                    'partner_id': log.partner_id.id or None,
                    'customer': log.partner_id.display_name or (log.partner_id.name if log.partner_id else 'No customer'),
                    'task': log.task_type_id.name or '',
                    'visit_type': 'Onsite' if is_onsite else 'Offsite',
                    'category_type': cat_type,
                    'is_planned': is_planned,
                    'is_unplanned': is_unplanned,
                })
        unplanned_count = sum(1 for t in tasks if t['is_unplanned'])
        unplanned_onsite_count = sum(1 for t in tasks if t['is_unplanned'] and t['visit_type'] == 'Onsite')
        planned_task_count = sum(1 for t in tasks if t['is_planned'])
        # Manager-assigned open tasks for today (ff.task assigned to employee, state todo/in_progress)
        manager_tasks = []
        if 'ff.task' in request.env:
            open_tasks = request.env['ff.task'].sudo().search([
                ('employee_id', '=', employee.id),
                ('state', 'in', ('todo', 'in_progress')),
            ])
            for t in open_tasks:
                manager_tasks.append({
                    'id': t.id,
                    'name': t.name,
                    'customer': ref(t.partner_id),
                    'due': t.date_deadline.isoformat() if t.date_deadline else None,
                    'state': t.state,
                    'priority': t.priority or '0',
                    'assigned_by': t.assigned_by_employee_id.name or t.assigned_by_id.name or None,
                    'visit_type': t.visit_id.visit_type if (t.visit_id and t.visit_id.visit_type) else 'offsite',
                })
        return ok({
            'tasks': tasks,
            'tasks_done': unplanned_count,
            'tasks_unplanned': unplanned_count,
            'tasks_unplanned_total': unplanned_count,
            'tasks_unplanned_onsite': unplanned_onsite_count,
            'tasks_planned': planned_task_count,
            'tasks_total': len(tasks),
            'tasks_onsite': sum(1 for t in tasks if t['visit_type'] == 'Onsite'),
            'tasks_offsite': sum(1 for t in tasks if t['visit_type'] == 'Offsite'),
            'tasks_manager': manager_tasks,
            'tasks_manager_count': len(manager_tasks),
            'date': day.isoformat(),
            'plan': plan_data(plans[:1]),
            'plans': [plan_data(p) for p in plans],
            'clients': rows,
            'adhoc_visits': [visit_data(v) for v in visits if v.partner_id not in planned_partners],
            'ongoing': visit_data(ongoing),
        })

    
    @api_route('/api/v1/beat/today/excel', methods=('GET',))
    def beat_today_excel(self, employee, date=None, **kw):
        """Single Excel file with two tabs: Planned Customers and Completed Tasks."""
        import io
        import re
        import xlsxwriter

        day = _day(employee, date)
        start, end = employee._ff_day_bounds(day)

        plans = request.env['ff.beat.plan'].sudo().search(
            [('employee_id', '=', employee.id), ('date', '=', day)], order='id')
        visits = request.env['ff.visit'].sudo().search([
            ('employee_id', '=', employee.id), ('check_in_at', '>=', start), ('check_in_at', '<', end),
        ], order='check_in_at asc')

        lines = plans.customer_line_ids.filtered('selected').sorted(lambda l: (l.day_id.id, l.sequence, l.id))
        planned_partner_ids = set(lines.mapped('partner_id.id'))

        # Prepare Tab 1: Planned Customers
        planned_rows = []
        for seq, line in enumerate(lines, start=1):
            p = line.partner_id
            p_visits = visits.filtered(lambda v, pid=p.id: v.partner_id.id == pid)
            if p_visits.filtered(lambda v: v.state == 'ongoing'):
                status = 'Ongoing'
            elif p_visits.filtered(lambda v: v.visit_type != 'offsite'):
                status = 'Visited'
            else:
                status = 'Cancelled' if line.cancelled else 'Pending'

            last_visit = p_visits[-1:] if p_visits else None
            visited_time = ''
            visit_type = ''
            if last_visit and last_visit.check_in_at and status in ('Visited', 'Ongoing'):
                local_dt = employee._ff_to_local(last_visit.check_in_at)
                visited_time = local_dt.strftime('%H:%M')
                visit_type = (last_visit.visit_type or '').capitalize()

            cat = getattr(p, 'ff_category_type', '') or ''
            cat_label = cat.capitalize() if cat else (p.ff_category_id.name if getattr(p, 'ff_category_id', None) else 'Outlet')
            address_parts = [part for part in [p.street, p.street2, p.city, p.zip] if part]
            address = ', '.join(address_parts)

            planned_rows.append({
                'seq': seq,
                'name': p.display_name or p.name or '',
                'category': cat_label,
                'beat': line.beat_id.name or '',
                'address': address,
                'phone': getattr(p, 'phone', None) or getattr(p, 'mobile', None) or '',
                'status': status,
                'time': visited_time,
                'visit_type': visit_type,
            })

        # Prepare Tab 2: Completed Tasks
        task_rows = []
        if 'ff.task.log' in request.env:
            for seq, log in enumerate(request.env['ff.task.log'].sudo().search([
                    ('employee_id', '=', employee.id), ('date', '>=', start), ('date', '<', end)], order='date asc'), start=1):
                is_onsite = bool(log.visit_id and log.visit_id.visit_type == 'onsite')
                is_planned = bool(log.partner_id and log.partner_id.id in planned_partner_ids)
                local_dt = employee._ff_to_local(log.date) if log.date else None
                cat = getattr(log.partner_id, 'ff_category_type', '') or ''
                cat_label = cat.capitalize() if cat else 'Outlet'
                task_rows.append({
                    'seq': seq,
                    'customer': log.partner_id.display_name or (log.partner_id.name if log.partner_id else '-'),
                    'category': cat_label,
                    'task': log.task_type_id.name or '',
                    'visit_type': 'Onsite' if is_onsite else 'Offsite',
                    'plan_type': 'Planned' if is_planned else 'Unplanned',
                    'time': local_dt.strftime('%H:%M') if local_dt else '',
                    'result': getattr(log, 'result', '') or getattr(log, 'note', '') or '',
                })

        # Build Excel
        buf = io.BytesIO()
        book = xlsxwriter.Workbook(buf, {'in_memory': True})

        fmt_title = book.add_format({'bold': True, 'font_size': 14, 'font_color': '#1B3A7A'})
        fmt_sub = book.add_format({'font_size': 10, 'font_color': '#555555'})
        fmt_head = book.add_format({'bold': True, 'bg_color': '#1B3A7A', 'font_color': '#FFFFFF', 'border': 1, 'align': 'center', 'valign': 'vcenter'})
        fmt_cell = book.add_format({'border': 1, 'valign': 'vcenter'})
        fmt_cell_center = book.add_format({'border': 1, 'align': 'center', 'valign': 'vcenter'})

        fmt_visited = book.add_format({'border': 1, 'bold': True, 'bg_color': '#E6F4EA', 'font_color': '#137333', 'align': 'center', 'valign': 'vcenter'})
        fmt_pending = book.add_format({'border': 1, 'bold': True, 'bg_color': '#FEF7E0', 'font_color': '#B06000', 'align': 'center', 'valign': 'vcenter'})
        fmt_cancelled = book.add_format({'border': 1, 'bold': True, 'bg_color': '#FCE8E6', 'font_color': '#C5221F', 'align': 'center', 'valign': 'vcenter'})
        fmt_planned = book.add_format({'border': 1, 'bold': True, 'bg_color': '#E8EFFF', 'font_color': '#1B3A7A', 'align': 'center', 'valign': 'vcenter'})
        fmt_unplanned = book.add_format({'border': 1, 'bold': True, 'bg_color': '#FFF0D4', 'font_color': '#B06000', 'align': 'center', 'valign': 'vcenter'})
        fmt_onsite = book.add_format({'border': 1, 'bg_color': '#E6F4EA', 'font_color': '#137333', 'align': 'center', 'valign': 'vcenter'})
        fmt_offsite = book.add_format({'border': 1, 'bg_color': '#F1F3F4', 'font_color': '#5F6368', 'align': 'center', 'valign': 'vcenter'})

        # --- Sheet 1: Planned Customers ---
        ws1 = book.add_worksheet('Planned Customers')
        ws1.write(0, 0, "Today's Beat Plan - Planned Customers", fmt_title)
        ws1.write(1, 0, 'Date: %s  |  Employee: %s' % (day.strftime('%d-%m-%Y'), employee.name), fmt_sub)

        headers1 = ['S.No', 'Customer Name', 'Category', 'Beat / Route', 'Address', 'Phone', 'Status', 'Visited Time', 'Visit Type']
        col_widths1 = [6, 32, 14, 22, 38, 16, 14, 14, 14]
        for col_idx, (h, w) in enumerate(zip(headers1, col_widths1)):
            ws1.write(3, col_idx, h, fmt_head)
            ws1.set_column(col_idx, col_idx, w)

        row_no = 4
        for r in planned_rows:
            ws1.write(row_no, 0, r['seq'], fmt_cell_center)
            ws1.write(row_no, 1, r['name'], fmt_cell)
            ws1.write(row_no, 2, r['category'], fmt_cell_center)
            ws1.write(row_no, 3, r['beat'], fmt_cell)
            ws1.write(row_no, 4, r['address'], fmt_cell)
            ws1.write(row_no, 5, r['phone'], fmt_cell_center)
            st = r['status']
            st_fmt = fmt_visited if st == 'Visited' else (fmt_cancelled if st == 'Cancelled' else fmt_pending)
            ws1.write(row_no, 6, st, st_fmt)
            ws1.write(row_no, 7, r['time'] or '-', fmt_cell_center)
            vt = r['visit_type']
            vt_fmt = fmt_onsite if vt == 'Onsite' else (fmt_offsite if vt == 'Offsite' else fmt_cell_center)
            ws1.write(row_no, 8, vt or '-', vt_fmt)
            row_no += 1

        if not planned_rows:
            ws1.write(row_no, 1, 'No planned customers for this date', fmt_cell)
            row_no += 1

        row_no += 1
        ws1.write(row_no, 0, 'Summary', book.add_format({'bold': True}))
        ws1.write(row_no + 1, 0, 'Total Planned:', book.add_format({'bold': True}))
        ws1.write(row_no + 1, 1, len(planned_rows))
        ws1.write(row_no + 2, 0, 'Visited:', book.add_format({'bold': True}))
        ws1.write(row_no + 2, 1, sum(1 for r in planned_rows if r['status'] == 'Visited'))
        ws1.write(row_no + 3, 0, 'Pending:', book.add_format({'bold': True}))
        ws1.write(row_no + 3, 1, sum(1 for r in planned_rows if r['status'] == 'Pending'))
        ws1.freeze_panes(4, 0)

        # --- Sheet 2: Completed Tasks ---
        ws2 = book.add_worksheet('Completed Tasks')
        ws2.write(0, 0, "Today's Beat Plan - Completed Tasks", fmt_title)
        ws2.write(1, 0, 'Date: %s  |  Employee: %s' % (day.strftime('%d-%m-%Y'), employee.name), fmt_sub)

        headers2 = ['S.No', 'Customer Name', 'Category', 'Task Name', 'Visit Type', 'Plan Status', 'Completed Time', 'Result / Details']
        col_widths2 = [6, 32, 14, 26, 14, 16, 16, 30]
        for col_idx, (h, w) in enumerate(zip(headers2, col_widths2)):
            ws2.write(3, col_idx, h, fmt_head)
            ws2.set_column(col_idx, col_idx, w)

        row_no = 4
        for r in task_rows:
            ws2.write(row_no, 0, r['seq'], fmt_cell_center)
            ws2.write(row_no, 1, r['customer'], fmt_cell)
            ws2.write(row_no, 2, r['category'], fmt_cell_center)
            ws2.write(row_no, 3, r['task'], fmt_cell)
            vt = r['visit_type']
            vt_fmt = fmt_onsite if vt == 'Onsite' else fmt_offsite
            ws2.write(row_no, 4, vt, vt_fmt)
            pt = r['plan_type']
            pt_fmt = fmt_planned if pt == 'Planned' else fmt_unplanned
            ws2.write(row_no, 5, pt, pt_fmt)
            ws2.write(row_no, 6, r['time'] or '-', fmt_cell_center)
            ws2.write(row_no, 7, r['result'] or '-', fmt_cell)
            row_no += 1

        if not task_rows:
            ws2.write(row_no, 1, 'No tasks completed for this date', fmt_cell)
            row_no += 1

        row_no += 1
        ws2.write(row_no, 0, 'Summary', book.add_format({'bold': True}))
        ws2.write(row_no + 1, 0, 'Total Completed Tasks:', book.add_format({'bold': True}))
        ws2.write(row_no + 1, 1, len(task_rows))
        ws2.write(row_no + 2, 0, 'Planned Tasks:', book.add_format({'bold': True}))
        ws2.write(row_no + 2, 1, sum(1 for r in task_rows if r['plan_type'] == 'Planned'))
        ws2.write(row_no + 3, 0, 'Unplanned Tasks:', book.add_format({'bold': True}))
        ws2.write(row_no + 3, 1, sum(1 for r in task_rows if r['plan_type'] == 'Unplanned'))
        ws2.write(row_no + 4, 0, 'Onsite Tasks:', book.add_format({'bold': True}))
        ws2.write(row_no + 4, 1, sum(1 for r in task_rows if r['visit_type'] == 'Onsite'))
        ws2.write(row_no + 5, 0, 'Offsite Tasks:', book.add_format({'bold': True}))
        ws2.write(row_no + 5, 1, sum(1 for r in task_rows if r['visit_type'] == 'Offsite'))
        ws2.freeze_panes(4, 0)

        book.close()
        excel_bytes = buf.getvalue()

        clean_name = re.sub(r'[^a-zA-Z0-9_-]', '_', employee.name or 'Employee')
        filename = 'Today_Beat_Plan_%s_%s.xlsx' % (clean_name, day.strftime('%Y%m%d'))
        return request.make_response(excel_bytes, headers=[
            ('Content-Type', 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'),
            ('Content-Disposition', 'attachment; filename="%s"' % filename),
            ('Content-Length', str(len(excel_bytes))),
        ])

    @api_route('/api/v1/visit-outcomes', methods=('GET',))
    def visit_outcomes(self, employee, partner_id=None, **kw):
        try:
            partner = visible_client(employee, int(partner_id))
        except (TypeError, ValueError):
            raise ApiError('partner_id is required.')
        outcomes = request.env['ff.visit.outcome'].ff_for(employee, partner)
        return ok([{
            'id': o.id,
            'name': o.name,
            'code': o.code or None,
            'productive': o.productive,
            'is_order': o.is_order,
            'requires_note': o.requires_note,
            'requires_photo': o.requires_photo,
        } for o in outcomes])
