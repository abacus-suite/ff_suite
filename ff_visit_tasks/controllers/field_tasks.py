"""What the app needs to run the six tasks.

The prefix is /api/v1/field-tasks because /api/v1/tasks already belongs to the
to-do list a manager hands out, which is a different thing entirely.
"""
from odoo import http
from odoo.http import request

from odoo.addons.ff_mobile_api.controllers.clients import client_domain, to_int, visible_client
from odoo.addons.ff_mobile_api.controllers.common import (
    ApiError, api_route, body, ok, ref, require_punched_in, scope_members)
from odoo.addons.ff_mobile_api.controllers.field_data import client_data

from ..models.ff_task_log import (
    DAMAGE_REASONS, FREE_REASONS, LEAD_OUTCOMES, MEETING_RESULTS, OUTLET_CATEGORIES, PERSON_MET)


def _options(pairs):
    return [{'code': code, 'name': name} for code, name in pairs]


def _product(product):
    return {
        'id': product.id,
        'name': product.display_name,
        # The small box beside the name: the Product Code only.
        'code': product.product_tmpl_id.ff_code() or None,
        'uom': product.uom_id.name,
    }


class FieldForceFieldTasksApi(http.Controller):

    @api_route('/api/v1/field-tasks/config', methods=('GET',))
    def config(self, employee, **kw):
        """The task list, the flavours and material to list, and every dropdown."""
        types = request.env['ff.task.type'].sudo().search([])
        Product = request.env['product.product']
        can_company = bool(employee.sudo().ff_team_id.ff_company_samples)
        if not can_company:
            emp = employee.sudo()
            if hasattr(emp, '_ff_has_company_location'):
                can_company = bool(emp._ff_has_company_location())
            elif 'ff_territory_ids' in emp._fields:
                terrs = emp.ff_territory_ids | (emp.ff_secondary_territory if 'ff_secondary_territory' in emp._fields else request.env['ff.territory'])
                can_company = any(getattr(t, 'is_company_location', False) or getattr(t, 'company_location', False) for t in terrs)

        return ok({
            'tasks': [{
                'code': task.code, 'name': task.name, 'steps': task.steps,
                'needs_contact': task.needs_contact, 'hint': task.hint or None,
                'category_ids': task.category_ids.ids,
                # The distance the person must be within to start the task; none when the office does not ask.
                'geofence_m': (task.geofence_radius or 200) if task.geofence_required else None,
            } for task in types],
            'flavours': [_product(p) for p in Product.ff_flavours()],
            'materials': [_product(p) for p in Product.ff_materials()],
            'company_samples': can_company,
            'lists': {
                'free_reasons': _options(FREE_REASONS),
                'damage_reasons': _options(DAMAGE_REASONS),
                'person_met': _options(PERSON_MET),
                'lead_outcomes': _options(LEAD_OUTCOMES),
                'meeting_results': _options(MEETING_RESULTS),
                'outlet_categories': _options(request.env['ff.task.log']._ff_outlet_categories()),
            },
        })

    @api_route('/api/v1/field-tasks/samples', methods=('GET',))
    def samples(self, employee, member=None, **kw):
        """Samples in hand: mine, or (for a manager) one teammate's or the whole team's."""
        Move = request.env['ff.sample.move'].sudo()
        people, _label = scope_members(employee, member)
        people = people if len(people) else employee

        def one(person):
            every = Move.search([('employee_id', '=', person.id)])
            return {
                'employee': ref(person),
                'on_hand': [{'product': {'id': p.id, 'name': p.display_name}, 'quantity': q}
                            for p, q in Move.ff_on_hand(person)],
                'taken': sum(every.mapped('qty_in')),
                'given': sum(every.mapped('qty_out')),
                'moves': [{
                    'date': m.date.isoformat() if m.date else None, 'direction': m.direction,
                    'product': m.product_id.display_name, 'quantity': m.quantity,
                    'source_type': m.source_type or None, 'contact': m.partner_id.display_name or None,
                } for m in every[:60]],
            }

        if len(people) == 1:
            return ok(one(people))
        rows = [one(person) for person in people]
        totals = {}
        for row in rows:
            for line in row['on_hand']:
                key = line['product']['id']
                totals.setdefault(key, {'product': line['product'], 'quantity': 0.0})['quantity'] += line['quantity']
        return ok({
            'team': rows, 'on_hand': list(totals.values()),
            'taken': sum(r['taken'] for r in rows), 'given': sum(r['given'] for r in rows), 'moves': [],
        })

    @api_route('/api/v1/field-tasks/leads-due', methods=('GET',))
    def leads_due(self, employee, **kw):
        """Leads waiting for a follow-up, with how overdue each is."""
        rows = request.env['ff.task.log'].ff_leads_due(employee)
        return ok([dict(client_data(row['partner']), follow_up=row['date'].isoformat(),
                        follow_up_status=row['status'], follow_up_days=row['days'])
                   for row in rows])

    @api_route('/api/v1/field-tasks/leads', methods=('GET',))
    def leads(self, employee, q=None, **kw):
        """Every lead the person may follow up, in two lists.

        Planned: leads with a follow-up date set (overdue, today or coming), nearest date first.
        Unplanned: every other lead, A to Z.
        """
        planned_rows = request.env['ff.task.log'].ff_leads_due(employee)
        needle = (q or '').strip().lower()
        planned = [dict(client_data(row['partner']), follow_up=row['date'].isoformat(),
                        follow_up_status=row['status'], follow_up_days=row['days'])
                   for row in planned_rows
                   if not needle or needle in (row['partner'].name or '').lower()]
        planned_ids = {row['partner'].id for row in planned_rows}
        domain = client_domain(employee) + [('ff_category_type', '=', 'lead')]
        if planned_ids:
            domain.append(('id', 'not in', list(planned_ids)))
        if needle:
            domain.append(('name', 'ilike', needle))
        others = request.env['res.partner'].sudo().search(domain, order='name', limit=500)
        return ok({'planned': planned, 'unplanned': [client_data(p) for p in others]})

    @api_route('/api/v1/field-tasks/submit', methods=('POST',))
    def submit(self, employee, **kw):
        """Record a finished task and everything it sets going."""
        data = body()
        require_punched_in(employee, 'record a task', data)
        partner_id = to_int(data.get('partner_id'))
        if partner_id:
            visible_client(employee, partner_id)
        log = request.env['ff.task.log'].ff_submit_from_app(employee, data)
        return ok({
            'id': log.id,
            'name': log.name,
            'partner': ref(log.partner_id),
            'onboard': log.onboard,
            'demands': [{'id': d.id, 'name': d.name} for d in log.demand_ids],
            'orders': [{'id': o.id, 'name': o.name} for o in log.order_ids],
            'notes': [{'id': n.id, 'name': n.name, 'kind': n.kind} for n in log.note_ids],
        }, status=201)
