from odoo import http
from odoo.http import request

from odoo.addons.ff_base.tools import to_iso
from odoo.addons.ff_mobile_api.controllers.clients import to_int, visible_client
from odoo.addons.ff_mobile_api.controllers.common import ApiError, api_route, body, ok, ref

from ..models.ff_form import CHOICE_TYPES, NUMERIC_TYPES, TRIGGERS


def question_data(question, partner=None):
    condition = question.visible_if_field_id
    return {
        'value': question._ff_partner_value(partner) if partner else None,
        'customer_field': bool(question.partner_field_id),
        'key': question.key,
        'label': question.name,
        'type': question.field_type,
        'required': question.required,
        'options': question._ff_options() if question.field_type in CHOICE_TYPES else None,
        'hint': question.help_text or None,
        'min': question.min_value or None if question.field_type in NUMERIC_TYPES else None,
        'max': question.max_value or None if question.field_type in NUMERIC_TYPES else None,
        'visible_if': {'key': condition.key, 'value': question.visible_if_value} if condition else None,
    }


def form_data(form, filled, partner=None):
    return {
        'at_checkout': form.at_checkout,
        'id': form.id,
        'name': form.name,
        'description': form.description or None,
        'trigger': form.trigger,
        'frequency': form.frequency,
        'mandatory': form.mandatory,
        'filled': filled,
        'questions': [question_data(q, partner) for q in form.field_ids.sorted('sequence')],
    }


def response_data(response):
    return {
        'id': response.id,
        'form': ref(response.form_id),
        'contact': ref(response.partner_id),
        'visit_id': response.visit_id.id or None,
        'submitted_at': to_iso(response.submitted_at),
        'answers': [{'question': line.field_label, 'answer': line.value_text} for line in response.line_ids],
    }


def own_visit(employee, visit_id):
    visit = request.env['ff.visit'].sudo().browse(to_int(visit_id) or []).exists()
    if visit_id and (not visit or visit.employee_id != employee):
        raise ApiError('Visit not found.', 404, 'not_found')
    return visit


class FieldForceFormsApi(http.Controller):

    @api_route('/api/v1/forms', methods=('GET',))
    def forms(self, employee, trigger='visit', partner_id=None, visit_id=None, **kw):
        if trigger not in dict(TRIGGERS):
            raise ApiError('Unknown trigger.')
        visit = own_visit(employee, visit_id)
        partner = visible_client(employee, to_int(partner_id)) if partner_id else visit.partner_id
        scoped_partner = partner if trigger in ('visit', 'contact') else None
        forms = request.env['ff.form']._ff_applicable(employee, trigger, scoped_partner)
        Response = request.env['ff.form.response']
        return ok([form_data(f, Response.ff_is_filled(employee, f, partner, visit), partner) for f in forms])

    @api_route('/api/v1/forms/<int:form_id>/responses', methods=('POST',))
    def submit(self, employee, form_id, **kw):
        form = request.env['ff.form'].sudo().browse(form_id).exists()
        if not form:
            raise ApiError('Form not found.', 404, 'not_found')
        data = body()
        if data.get('partner_id'):
            visible_client(employee, to_int(data['partner_id']))
        response = request.env['ff.form.response'].ff_submit(employee, form, data)
        return ok(response_data(response), status=201)

    @api_route('/api/v1/forms/responses', methods=('GET',))
    def responses(self, employee, partner_id=None, form_id=None, limit=None, **kw):
        domain = [('employee_id', '=', employee.id)]
        if partner_id:
            domain.append(('partner_id', '=', to_int(partner_id)))
        if form_id:
            domain.append(('form_id', '=', to_int(form_id)))
        responses = request.env['ff.form.response'].sudo().search(domain, limit=min(to_int(limit) or 50, 200))
        return ok([response_data(r) for r in responses])


class FieldForceFormsExport(http.Controller):

    @http.route('/ff_forms/<int:form_id>/export/<string:kind>', type='http', auth='user', methods=['GET'])
    def export(self, form_id, kind, **kw):
        if not request.env.user.has_group('ff_base.group_ff_manager'):
            return request.not_found()
        form = request.env['ff.form'].browse(form_id).exists()
        if not form or kind not in ('responses', 'customers'):
            return request.not_found()
        content = form.ff_export_responses() if kind == 'responses' else form.ff_export_customers()
        name = '%s_%s.xlsx' % (form.name.replace(' ', '_').replace('/', '_'), kind)
        return request.make_response(content, headers=[
            ('Content-Type', 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'),
            ('Content-Disposition', 'attachment; filename="%s"' % name),
        ])
