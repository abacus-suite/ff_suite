"""What a salesperson has asked for that is still waiting, and who has to decide it."""
import re

from odoo import http
from odoo.http import request

from odoo.addons.ff_base.tools import to_iso

from .common import api_route, ok


def _digits(value):
    return re.sub(r'\D', '', value or '') or None


def _person(employee):
    """Who to ask: name and a number to call."""
    if not employee:
        return None
    phone = employee.mobile_phone or employee.work_phone or None
    return {'name': employee.name, 'phone': _digits(phone), 'role': employee.job_title or None}


class FieldForceMyPendingApi(http.Controller):

    @api_route('/api/v1/my-pending', methods=('GET',))
    def my_pending(self, employee, **kw):
        env = request.env
        manager = employee.sudo().parent_id
        approver = _person(manager)
        groups = []

        def add(key, title, rows):
            if rows:
                groups.append({'key': key, 'title': title, 'count': len(rows), 'items': rows})

        def search(model, domain, **kw_):
            return env[model].sudo().search(domain, **kw_) if model in env else []

        # ---- leave: the approver is whoever the type's flow names
        rows = []
        for leave in search('hr.leave', [('employee_id', '=', employee.id), ('state', 'in', ('confirm', 'validate1'))], limit=50):
            who = approver
            try:
                steps = leave._ff_approval_payload().get('steps') or []
                waiting = next((s for s in steps if s.get('state') in ('pending', 'waiting')), None)
                if waiting and waiting.get('approver') and waiting['approver'] not in ('HR', 'Manager'):
                    who = {'name': waiting['approver'], 'phone': None, 'role': waiting.get('name')}
            except Exception:  # noqa: BLE001
                pass
            rows.append({
                'id': leave.id, 'title': leave.holiday_status_id.name,
                'subtitle': '%s%s · %s day(s)' % (leave.request_date_from, (' to %s' % leave.request_date_to) if leave.request_date_to != leave.request_date_from else '', '%g' % leave.number_of_days),
                'amount': None, 'date': to_iso(leave.create_date), 'approver': who})
        add('leaves', 'Time off', rows)

        rows = [{'id': c.id, 'title': c.category_id.name or 'Expense', 'subtitle': str(c.date),
                 'amount': c.amount, 'currency': c.currency_id.name, 'date': to_iso(c.create_date), 'approver': approver}
                for c in search('ff.expense.claim', [('employee_id', '=', employee.id), ('state', '=', 'submitted')], limit=50)]
        add('expenses', 'Expense claims', rows)

        rows = [{'id': c.id, 'title': 'Travel allowance', 'subtitle': str(c.date), 'amount': c.amount,
                 'currency': c.currency_id.name, 'date': to_iso(c.create_date), 'approver': approver}
                for c in search('ff.allowance.claim', [('employee_id', '=', employee.id), ('state', '=', 'submitted')], limit=50)]
        add('allowances', 'Travel allowance', rows)

        rows = [{'id': r.id, 'title': r.name or 'Return', 'subtitle': r.partner_id.display_name if 'partner_id' in r._fields else '',
                 'amount': getattr(r, 'amount_total', None), 'currency': r.currency_id.name if 'currency_id' in r._fields else None,
                 'date': to_iso(r.create_date), 'approver': approver}
                for r in search('ff.return', [('employee_id', '=', employee.id), ('state', '=', 'submitted')], limit=50)]
        add('returns', 'Returns', rows)

        rows = [{'id': r.id, 'title': 'Attendance fix', 'subtitle': str(r.date), 'amount': None,
                 'date': to_iso(r.create_date), 'approver': approver}
                for r in search('ff.regularisation', [('employee_id', '=', employee.id), ('state', '=', 'submitted')], limit=50)]
        add('regularisation', 'Attendance fixes', rows)

        rows = [{'id': c.id, 'title': c.name, 'subtitle': 'New contact · %s' % (c.ff_category_id.name or ''), 'amount': None,
                 'date': to_iso(c.create_date), 'approver': approver}
                for c in search('res.partner', [('ff_is_client', '=', True), ('ff_approval_state', '=', 'pending'),
                                                ('ff_created_by_employee_id', '=', employee.id)], limit=50)]
        add('contacts', 'New contacts', rows)

        rows = [{'id': r.id, 'title': '%s (%s)' % (r.target, r.scope_type), 'subtitle': '%s to %s' % (r.date_from, r.date_to),
                 'amount': None, 'date': to_iso(r.create_date), 'approver': approver}
                for r in search('ff.contact.access.request', [('employee_id', '=', employee.id), ('state', '=', 'pending')], limit=50)]
        add('access', 'Contact access', rows)

        rows = [{'id': h.id, 'title': 'Handover to %s' % h.distributor_id.name, 'subtitle': '%s · %s collection(s)' % (h.name, h.count),
                 'amount': h.amount, 'currency': h.currency_id.name, 'date': to_iso(h.date), 'approver': approver}
                for h in search('ff.distributor.handover', [('employee_id', '=', employee.id), ('state', '=', 'handed')], limit=50)]
        add('handovers', 'Handovers', rows)

        rows = [{'id': d.id, 'title': 'Deposit %s' % d.name, 'subtitle': '%s collection(s)' % d.collection_count,
                 'amount': d.amount, 'currency': d.currency_id.name, 'date': to_iso(d.submitted_at), 'approver': approver}
                for d in search('ff.collection.deposit', [('employee_id', '=', employee.id), ('state', '=', 'submitted')], limit=50)]
        add('deposits', 'Money submitted to the office', rows)

        rows = [{'id': n.id, 'title': '%s · %s' % (n.name, 'Debit' if n.kind == 'debit' else 'Credit'),
                 'subtitle': n.reason or '', 'amount': n.amount, 'currency': n.currency_id.name, 'date': to_iso(n.date), 'approver': approver}
                for n in search('ff.distributor.note', [('employee_id', '=', employee.id), ('state', '=', 'pending')], limit=50)]
        add('notes', 'Debit / credit notes', rows)

        rows = [{'id': b.id, 'title': b.name, 'subtitle': 'Beat you drew', 'amount': None,
                 'date': to_iso(b.create_date), 'approver': approver}
                for b in search('ff.beat', [('ff_approval_state', '=', 'pending'), ('ff_created_by_employee_id', '=', employee.id)], limit=50)]
        add('beats', 'New beats', rows)

        # ---- demands waiting for a distributor: the one to ask is the distributor
        rows = []
        for d in search('ff.demand', [('employee_id', '=', employee.id), ('state', '=', 'waiting')], limit=50):
            dist = d.distributor_id
            rows.append({
                'id': d.id, 'title': d.name, 'subtitle': 'Waiting for %s · %s' % (dist.name or 'a distributor', d.partner_id.display_name),
                'amount': d.amount_total, 'currency': d.currency_id.name, 'date': to_iso(d.date),
                'approver': {'name': dist.name, 'phone': _digits(dist.phone or getattr(dist, 'mobile', '')), 'role': 'Distributor'} if dist else None})
        add('demands', 'Demands with a distributor', rows)

        return ok({'total': sum(g['count'] for g in groups), 'groups': groups, 'manager': approver})
