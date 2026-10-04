"""What the app needs to run the six tasks.

The prefix is /api/v1/field-tasks because /api/v1/tasks already belongs to the
to-do list a manager hands out, which is a different thing entirely.
"""
from odoo import http
from odoo.http import request

from odoo.addons.ff_mobile_api.controllers.clients import to_int, visible_client
from odoo.addons.ff_mobile_api.controllers.common import ApiError, api_route, body, ok, ref, require_punched_in
from odoo.addons.ff_mobile_api.controllers.field_data import client_data

from ..models.ff_task_log import (
    DAMAGE_REASONS, FREE_REASONS, LEAD_OUTCOMES, MEETING_RESULTS, OUTLET_CATEGORIES, PERSON_MET)


def _options(pairs):
    return [{'code': code, 'name': name} for code, name in pairs]


def _product(product):
    return {
        'id': product.id,
        'name': product.display_name,
        # What a flavour is called on the screen: its code, where it has one.
        'code': product.default_code or product.product_tmpl_id.ff_sku_code or None,
        'uom': product.uom_id.name,
    }


class FieldForceFieldTasksApi(http.Controller):

    @api_route('/api/v1/field-tasks/config', methods=('GET',))
    def config(self, employee, **kw):
        """The task list, the flavours and material to list, and every dropdown."""
        types = request.env['ff.task.type'].sudo().search([])
        Product = request.env['product.product']
        return ok({
            'tasks': [{
                'code': task.code, 'name': task.name, 'steps': task.steps,
                'needs_contact': task.needs_contact, 'hint': task.hint or None,
            } for task in types],
            'flavours': [_product(p) for p in Product.ff_flavours()],
            'materials': [_product(p) for p in Product.ff_materials()],
            'company_samples': bool(employee.sudo().ff_team_id.ff_company_samples),
            'lists': {
                'free_reasons': _options(FREE_REASONS),
                'damage_reasons': _options(DAMAGE_REASONS),
                'person_met': _options(PERSON_MET),
                'lead_outcomes': _options(LEAD_OUTCOMES),
                'meeting_results': _options(MEETING_RESULTS),
                'outlet_categories': _options(OUTLET_CATEGORIES),
            },
        })

    @api_route('/api/v1/field-tasks/leads-due', methods=('GET',))
    def leads_due(self, employee, **kw):
        """Leads waiting for a follow-up, with how overdue each is."""
        rows = request.env['ff.task.log'].ff_leads_due(employee)
        return ok([dict(client_data(row['partner']), follow_up=row['date'].isoformat(),
                        follow_up_status=row['status'], follow_up_days=row['days'])
                   for row in rows])

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
            'notes': [{'id': n.id, 'name': n.name, 'kind': n.kind} for n in log.note_ids],
        }, status=201)
