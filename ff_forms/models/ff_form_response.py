from odoo import api, fields, models
from odoo.exceptions import AccessError, ValidationError

MAX_PHOTOS_PER_QUESTION = 5


def _strip_data_url(image):
    if isinstance(image, str) and image.startswith('data:') and ',' in image:
        return image.split(',', 1)[1]
    return image


def _to_int(value):
    try:
        return int(value)
    except (TypeError, ValueError):
        return None


class FfFormResponse(models.Model):
    _name = 'ff.form.response'
    _description = 'Field Form Response'
    _inherit = ['mail.thread']
    _order = 'submitted_at desc, id desc'

    form_id = fields.Many2one('ff.form', required=True, index=True, ondelete='restrict')
    employee_id = fields.Many2one('hr.employee', required=True, index=True, ondelete='cascade')
    team_id = fields.Many2one(related='employee_id.ff_team_id', store=True)
    department_id = fields.Many2one(related='employee_id.department_id', store=True)
    partner_id = fields.Many2one('res.partner', string='Contact', index=True)
    visit_id = fields.Many2one('ff.visit', index=True, ondelete='set null')
    submitted_at = fields.Datetime(required=True, default=fields.Datetime.now, index=True)
    answers = fields.Json()
    latitude = fields.Float(digits=(10, 7))
    longitude = fields.Float(digits=(10, 7))
    line_ids = fields.One2many('ff.form.response.line', 'response_id', string='Answers')
    client_uuid = fields.Char(index=True, copy=False)

    _client_uuid_uniq = models.Constraint('UNIQUE(client_uuid)', 'This response was already received.')

    @api.depends('form_id', 'partner_id', 'submitted_at')
    def _compute_display_name(self):
        for response in self:
            response.display_name = ' - '.join(filter(None, [
                response.form_id.name, response.partner_id.name, str(response.submitted_at or '')]))

    @api.model
    def _ff_filled_domain(self, employee, form, partner, visit):
        """Domain of earlier responses that block a new one, or None when unlimited."""
        if form.frequency == 'visit':
            return [('form_id', '=', form.id), ('visit_id', '=', visit.id)] if visit else None
        if form.frequency == 'contact':
            return [('form_id', '=', form.id), ('partner_id', '=', partner.id)] if partner else None
        if form.frequency == 'day':
            start, end = employee._ff_day_bounds(employee._ff_today())
            return [('form_id', '=', form.id), ('employee_id', '=', employee.id),
                    ('submitted_at', '>=', start), ('submitted_at', '<', end)]
        return None

    @api.model
    def ff_is_filled(self, employee, form, partner=None, visit=None):
        domain = self._ff_filled_domain(employee, form, partner, visit)
        return bool(domain) and bool(self.sudo().search_count(domain, limit=1))

    @api.model
    def ff_submit(self, employee, form, data):
        """Validate and store a response sent by the app. Idempotent on ``uuid``."""
        Response = self.sudo()
        uuid = data.get('uuid') or False
        if uuid:
            existing = Response.search([('client_uuid', '=', uuid)], limit=1)
            if existing:
                return existing

        Partner, Visit = self.env['res.partner'].sudo(), self.env['ff.visit'].sudo()
        partner = Partner.browse(_to_int(data.get('partner_id')) or []).exists()
        visit = Visit.browse(_to_int(data.get('visit_id')) or []).exists()
        if visit and visit.employee_id != employee:
            raise AccessError(self.env._('This visit is not yours.'))
        partner = partner or visit.partner_id
        if form.trigger in ('visit', 'contact') and not partner:
            raise ValidationError(self.env._('Choose the contact for this form.'))
        if form.trigger == 'visit' and not visit:
            visit = Visit.search([('employee_id', '=', employee.id), ('partner_id', '=', partner.id),
                                  ('state', '=', 'ongoing')], limit=1)
            if not visit:
                raise ValidationError(self.env._('Check in at %s before filling this form.', partner.name))
        scoped_partner = partner if form.trigger in ('visit', 'contact') else None
        if form not in self.env['ff.form']._ff_applicable(employee, form.trigger, scoped_partner):
            raise AccessError(self.env._('This form is not available to you.'))
        if self.ff_is_filled(employee, form, partner, visit):
            raise ValidationError(self.env._('"%s" was already filled.', form.name))

        photos = data.get('photos') if isinstance(data.get('photos'), dict) else {}
        photo_questions = form.field_ids.filtered(lambda q: q.field_type == 'photo')
        photo_counts = {q.key: len([p for p in photos.get(q.key) or [] if isinstance(p, str) and p])
                        for q in photo_questions}
        answers = form._ff_validate(data.get('answers') or {}, photo_counts)

        response = Response.create({
            'form_id': form.id,
            'employee_id': employee.id,
            'partner_id': partner.id or False,
            'visit_id': visit.id or False,
            'latitude': data.get('lat') or 0.0,
            'longitude': data.get('lng') or 0.0,
            'answers': answers,
            'client_uuid': uuid,
            'line_ids': [(0, 0, vals) for vals in self._ff_line_vals(form, answers)],
        })
        stored = dict(answers)
        for question in photo_questions:
            if not question._ff_is_visible(answers):
                continue
            images = [p for p in photos.get(question.key) or [] if isinstance(p, str) and p][:MAX_PHOTOS_PER_QUESTION]
            if images:
                attachments = self.env['ir.attachment'].sudo().create([{
                    'name': '%s_%s.jpg' % (question.key, index + 1),
                    'datas': _strip_data_url(image),
                    'res_model': self._name,
                    'res_id': response.id,
                    'mimetype': 'image/jpeg',
                } for index, image in enumerate(images)])
                stored[question.key] = attachments.ids
                response.line_ids = [(0, 0, {'field_id': question.id, 'field_label': question.name,
                                             'value_text': self.env._('%s photo(s)', len(images)),
                                             'value_number': len(images)})]
        if stored != answers:
            response.answers = stored
        return response

    @api.model
    def _ff_line_vals(self, form, answers):
        """One reportable row per answered question."""
        vals_list = []
        for question in form.field_ids.sorted('sequence'):
            if question.key not in answers:
                continue
            value = answers[question.key]
            if isinstance(value, bool):
                text, number = (self.env._('Yes') if value else self.env._('No')), float(value)
            elif isinstance(value, (int, float)):
                text, number = str(value), float(value)
            elif isinstance(value, list):
                text, number = ', '.join(value), float(len(value))
            else:
                text, number = str(value), 0.0
            vals_list.append({'field_id': question.id, 'field_label': question.name,
                              'value_text': text, 'value_number': number})
        return vals_list


class FfFormResponseLine(models.Model):
    _name = 'ff.form.response.line'
    _description = 'Field Form Answer'
    _order = 'response_id, id'

    response_id = fields.Many2one('ff.form.response', required=True, index=True, ondelete='cascade')
    form_id = fields.Many2one(related='response_id.form_id', store=True)
    employee_id = fields.Many2one(related='response_id.employee_id', store=True)
    partner_id = fields.Many2one(related='response_id.partner_id', store=True)
    submitted_at = fields.Datetime(related='response_id.submitted_at', store=True)
    field_id = fields.Many2one('ff.form.field', string='Question', ondelete='set null', index=True)
    field_label = fields.Char(string='Question Text')
    value_text = fields.Char(string='Answer')
    value_number = fields.Float(string='Numeric Answer', digits=(16, 2))
