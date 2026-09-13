"""Excel sheets of a form: every answer given, or every customer with their current values."""
import io

import xlsxwriter

from odoo import fields, models


class FfFormExport(models.Model):
    _inherit = 'ff.form'

    def action_download_responses(self):
        self.ensure_one()
        return {'type': 'ir.actions.act_url', 'url': '/ff_forms/%d/export/responses' % self.id, 'target': 'self'}

    def action_download_customers(self):
        self.ensure_one()
        return {'type': 'ir.actions.act_url', 'url': '/ff_forms/%d/export/customers' % self.id, 'target': 'self'}

    # ------------------------------------------------------------------
    def _ff_book(self, title, headers, rows):
        buffer = io.BytesIO()
        book = xlsxwriter.Workbook(buffer, {'in_memory': True})
        sheet = book.add_worksheet(title[:31])
        head = book.add_format({'bold': True, 'bg_color': '#E8EFFF', 'border': 1, 'text_wrap': True})
        linked = book.add_format({'bold': True, 'bg_color': '#DCFCE7', 'border': 1, 'text_wrap': True})
        for index, (label, is_linked) in enumerate(headers):
            sheet.write(0, index, label, linked if is_linked else head)
            sheet.set_column(index, index, 22)
        for row_no, row in enumerate(rows, 1):
            for index, value in enumerate(row):
                if value is None or value is False:
                    continue
                if isinstance(value, (list, tuple)):
                    value = ', '.join(str(v) for v in value)
                sheet.write(row_no, index, value if isinstance(value, (int, float)) else str(value))
        sheet.freeze_panes(1, 0)
        sheet.autofilter(0, 0, max(len(rows), 1), max(len(headers) - 1, 0))
        book.close()
        return buffer.getvalue()

    def _ff_questions(self):
        return self.field_ids.filtered(lambda q: q.field_type != 'photo').sorted('sequence')

    def ff_export_responses(self):
        """One row per response: when, who, customer, then one column per question."""
        self.ensure_one()
        questions = self._ff_questions()
        headers = [('Submitted', False), ('Employee', False), ('Customer', False), ('Visit', False)]
        headers += [(q.name + (' → %s' % q.partner_field_id.field_description if q.partner_field_id else ''),
                     bool(q.partner_field_id)) for q in questions]
        rows = []
        for response in self.env['ff.form.response'].sudo().search([('form_id', '=', self.id)], order='submitted_at desc'):
            answers = response.answers or {}
            local = response.employee_id._ff_to_local(response.submitted_at) if response.submitted_at else None
            rows.append([
                local.strftime('%Y-%m-%d %H:%M') if local else None,
                response.employee_id.name, response.partner_id.display_name, response.visit_id.display_name,
            ] + [answers.get(q.key) for q in questions])
        return self._ff_book(self.name, headers, rows)

    def ff_export_customers(self):
        """One row per customer the form applies to: current customer values and the latest answers."""
        self.ensure_one()
        questions = self._ff_questions()
        domain = [('ff_is_client', '=', True), ('company_id', 'in', (False, self.company_id.id))]
        if self.category_ids:
            domain.append(('ff_category_id', 'in', self.category_ids.ids))
        partners = self.env['res.partner'].sudo().search(domain, order='name')
        latest = {}
        for response in self.env['ff.form.response'].sudo().search(
                [('form_id', '=', self.id), ('partner_id', 'in', partners.ids)], order='submitted_at asc'):
            latest[response.partner_id.id] = response
        headers = [('Customer', False), ('Code', False), ('City', False), ('Category', False),
                   ('Last filled', False), ('Filled by', False)]
        headers += [(q.name + (' (customer field)' if q.partner_field_id else ''), bool(q.partner_field_id))
                    for q in questions]
        rows = []
        for partner in partners:
            response = latest.get(partner.id)
            answers = (response.answers or {}) if response else {}
            row = [partner.display_name, partner.ff_client_code, partner.city, partner.ff_category_id.name,
                   fields.Datetime.to_string(response.submitted_at) if response else None,
                   response.employee_id.name if response else None]
            for question in questions:
                value = question._ff_partner_value(partner) if question.partner_field_id else None
                row.append(value if value is not None else answers.get(question.key))
            rows.append(row)
        return self._ff_book('%s customers' % self.name, headers, rows)
