"""Expense Payment Request API: the company pays a vendor, against a tax invoice or a quotation."""
from odoo import http
from odoo.exceptions import UserError
from odoo.http import request

from odoo.addons.ff_base.tools import to_iso
from odoo.addons.ff_mobile_api.controllers.clients import to_int
from odoo.addons.ff_mobile_api.controllers.common import ApiError, api_route, body, ok, ref


def request_data(rec):
    return {
        'id': rec.id,
        'name': rec.name,
        'category': ref(rec.category_id),
        'sub_category': ref(rec.sub_category_id),
        'amount': rec.amount,
        'currency': rec.currency_id.name,
        'document': rec.document,
        'state': rec.state,
        'date': to_iso(rec.date),
        'paid_on': to_iso(rec.paid_on),
        'invoice_due': to_iso(rec.invoice_due),
        'reason': rec.reject_reason or None,
    }


class FieldForceExpenseRequestsApi(http.Controller):

    @api_route('/api/v1/expense-requests', methods=('GET',))
    def listing(self, employee, **kw):
        rows = request.env['ff.expense.request'].sudo().search([('employee_id', '=', employee.id)], limit=100)
        return ok({'requests': [request_data(r) for r in rows]})

    @api_route('/api/v1/expense-requests', methods=('POST',))
    def create(self, employee, **kw):
        data = body()
        Request = request.env['ff.expense.request'].sudo()
        uuid = data.get('uuid') if isinstance(data.get('uuid'), str) else None
        if uuid:
            again = Request.search([('client_uuid', '=', uuid), ('employee_id', '=', employee.id)], limit=1)
            if again:
                return ok(request_data(again), status=201)
        Category = request.env['ff.expense.category'].sudo()
        category = Category.browse(to_int(data.get('category_id'))).exists()
        if not category or category.parent_id:
            raise ApiError('Choose the expense category.')
        sub = Category.browse(to_int(data.get('sub_category_id'))).exists() if data.get('sub_category_id') else Category
        if sub and sub.parent_id != category:
            raise ApiError('That sub category does not belong to the category.')
        if category.child_ids and not sub:
            raise ApiError('Choose the sub category.')
        try:
            amount = float(data.get('amount'))
        except (TypeError, ValueError):
            raise ApiError('The amount must be a number.')
        if amount <= 0:
            raise ApiError('The amount must be more than zero.')
        document = data.get('document')
        if document not in ('tax_invoice', 'quotation'):
            raise ApiError('Choose tax invoice or quotation.')
        label = 'tax invoice' if document == 'tax_invoice' else 'quotation'
        if not data.get('photo'):
            raise ApiError('A photo of the %s is needed.' % label)
        vals = {
            'employee_id': employee.id, 'category_id': category.id, 'sub_category_id': sub.id or False,
            'amount': amount, 'document': document, 'client_uuid': uuid,
        }
        if data.get('date'):
            vals['date'] = data['date']
        try:
            rec = Request.create(vals)
            rec._ff_attach(data['photo'], label)
        except UserError as error:
            request.env.cr.rollback()
            raise ApiError(str(error), 400, 'invalid')
        return ok(request_data(rec), status=201)

    @api_route('/api/v1/expense-requests/<int:request_id>/invoice', methods=('POST',))
    def invoice(self, employee, request_id, **kw):
        rec = request.env['ff.expense.request'].sudo().browse(request_id).exists()
        if not rec or rec.employee_id != employee:
            raise ApiError('Request not found.', 404, 'not_found')
        try:
            rec.ff_upload_invoice(body().get('photo'))
        except UserError as error:
            request.env.cr.rollback()
            raise ApiError(str(error), 400, 'invalid')
        return ok(request_data(rec))
