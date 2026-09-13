import re

from odoo import api, fields, models
from odoo.exceptions import ValidationError

TRIGGERS = [
    ('visit', 'During a visit'),
    ('contact', 'Contact profile'),
    ('standalone', 'Anytime from the app'),
    ('punch_in', 'At punch-in'),
]
FREQUENCIES = [
    ('any', 'Any number of times'),
    ('visit', 'Every visit (each check-out)'),
    ('contact', 'One time per contact'),
    ('month', 'Once a month per contact'),
    ('day', 'Once per day'),
]
# Customer fields a question can read from and write back to.
PARTNER_FIELD_TYPES = {
    'char': 'text', 'text': 'textarea', 'html': 'textarea', 'integer': 'number', 'float': 'decimal',
    'monetary': 'decimal', 'boolean': 'checkbox', 'date': 'date', 'selection': 'select',
}
DEFAULT_FREQUENCY = {'visit': 'visit', 'contact': 'contact', 'standalone': 'any', 'punch_in': 'day'}
FIELD_TYPES = [
    ('text', 'Short text'),
    ('textarea', 'Long text'),
    ('number', 'Whole number'),
    ('decimal', 'Decimal number'),
    ('date', 'Date'),
    ('select', 'Single choice'),
    ('multiselect', 'Multiple choice'),
    ('checkbox', 'Yes / No'),
    ('rating', 'Rating (1-5)'),
    ('photo', 'Photo'),
    ('phone', 'Phone'),
    ('email', 'Email'),
]
CHOICE_TYPES = ('select', 'multiselect')
NUMERIC_TYPES = ('number', 'decimal')


def _slug(text):
    return re.sub(r'[^a-z0-9]+', '_', (text or '').lower()).strip('_') or 'field'


class FfForm(models.Model):
    _name = 'ff.form'
    _description = 'Field Form'
    _inherit = ['mail.thread']
    _order = 'sequence, name'

    name = fields.Char(required=True, tracking=True, translate=True)
    description = fields.Text(translate=True)
    sequence = fields.Integer(default=10)
    trigger = fields.Selection(TRIGGERS, required=True, default='visit', tracking=True)
    frequency = fields.Selection(FREQUENCIES, required=True, default='visit', tracking=True)
    at_checkout = fields.Boolean(
        string='Ask at Check-out', tracking=True,
        help='The app shows this form on the check-out screen. With "Every visit" it is asked at each check-out; '
             'with "One time per contact" only until it has been filled once for that customer.')
    mandatory = fields.Boolean(tracking=True,
                               help='Visit forms must be filled before check-out; punch-in forms before punching in.')
    department_ids = fields.Many2many('hr.department', string='Departments', help='Leave empty for every department.')
    category_ids = fields.Many2many('ff.contact.category', string='Contact Categories',
                                    help='For visit / contact forms. Leave empty for every category.')
    field_ids = fields.One2many('ff.form.field', 'form_id', string='Questions', copy=True)
    response_count = fields.Integer(compute='_compute_response_count')
    company_id = fields.Many2one('res.company', required=True, default=lambda self: self.env.company)
    active = fields.Boolean(default=True)

    @api.onchange('trigger')
    def _onchange_trigger(self):
        self.frequency = DEFAULT_FREQUENCY.get(self.trigger, 'any')

    @api.constrains('trigger', 'frequency')
    def _check_frequency(self):
        for form in self:
            if form.frequency == 'visit' and form.trigger != 'visit':
                raise ValidationError(self.env._('"Once per visit" is only for visit forms.'))
            if form.frequency in ('contact', 'month') and form.trigger not in ('visit', 'contact'):
                raise ValidationError(self.env._('"Per contact" frequencies need a visit or contact form.'))

    def _compute_response_count(self):
        counts = dict(self.env['ff.form.response']._read_group([('form_id', 'in', self.ids)], ['form_id'], ['__count']))
        for form in self:
            form.response_count = counts.get(form, 0)

    @api.model
    def _ff_applicable(self, employee, trigger, partner=None):
        """Forms of ``trigger`` for ``employee`` (and ``partner``'s category)."""
        employee = employee.sudo()
        forms = self.sudo().search([
            ('trigger', '=', trigger),
            ('company_id', 'in', employee.company_id.ids),
            '|', ('department_ids', '=', False), ('department_ids', 'in', employee.department_id.ids),
        ])
        if partner is not None:
            category = partner.ff_category_id
            forms = forms.filtered(lambda f: not f.category_ids or category in f.category_ids)
        return forms

    def _ff_validate(self, answers, photo_counts=None):
        """Clean answers of visible questions; raise one ValidationError listing all problems."""
        self.ensure_one()
        answers = answers if isinstance(answers, dict) else {}
        photo_counts = photo_counts or {}
        cleaned, errors = {}, []
        for question in self.field_ids.sorted('sequence'):
            if not question._ff_is_visible(answers):
                continue
            if question.field_type == 'photo':
                if question.required and not photo_counts.get(question.key):
                    errors.append(self.env._('%s: add a photo.', question.name))
                continue
            try:
                value = question._ff_clean(answers.get(question.key))
            except ValueError as e:
                errors.append('%s: %s' % (question.name, e))
                continue
            if value is None:
                if question.required:
                    errors.append(self.env._('%s is required.', question.name))
                continue
            cleaned[question.key] = value
        if errors:
            raise ValidationError('\n'.join(errors))
        return cleaned

    def action_view_responses(self):
        self.ensure_one()
        action = self.env['ir.actions.act_window']._for_xml_id('ff_forms.ff_form_response_action')
        action['domain'] = [('form_id', '=', self.id)]
        action['context'] = {}
        return action


class FfFormField(models.Model):
    _name = 'ff.form.field'
    _description = 'Field Form Question'
    _order = 'sequence, id'

    form_id = fields.Many2one('ff.form', required=True, index=True, ondelete='cascade')
    sequence = fields.Integer(default=10)
    name = fields.Char(string='Question', required=True, translate=True)
    key = fields.Char(string='Technical Key', help='Stable identifier used in answers and exports.')
    field_type = fields.Selection(FIELD_TYPES, string='Type', required=True, default='text')
    required = fields.Boolean()
    options = fields.Text(help='Choices, one per line (single / multiple choice).')
    help_text = fields.Char(string='Hint', translate=True)
    min_value = fields.Float(string='Minimum', help='0 = no minimum (numbers only).')
    max_value = fields.Float(string='Maximum', help='0 = no maximum (numbers only).')
    partner_field_id = fields.Many2one(
        'ir.model.fields', string='Customer Field', ondelete='set null',
        domain="[('model', '=', 'res.partner'), ('store', '=', True), ('readonly', '=', False), "
               "('ttype', 'in', ['char', 'text', 'html', 'integer', 'float', 'monetary', 'boolean', 'date', 'selection'])]",
        help='Link the question to a field on the customer. The app shows the current value, and the answer is '
             'written back to the customer when the form is sent.')
    write_to_partner = fields.Boolean(string='Save Answer on Customer', default=True)
    visible_if_field_id = fields.Many2one('ff.form.field', string='Show Only When', ondelete='set null',
                                          help='Show this question only when another question has a given answer.')
    visible_if_value = fields.Char(string='Has Answer', help='For Yes / No questions use "yes" or "no".')

    _form_key_uniq = models.Constraint('UNIQUE(form_id, key)', 'Question keys must be unique within a form.')

    @api.model_create_multi
    def create(self, vals_list):
        taken = {}
        for vals in vals_list:
            if vals.get('key') or not vals.get('form_id'):
                continue
            form_id = vals['form_id']
            if form_id not in taken:
                taken[form_id] = set(self.search([('form_id', '=', form_id)]).mapped('key'))
            base = key = _slug(vals.get('name'))
            index = 2
            while key in taken[form_id]:
                key, index = '%s_%s' % (base, index), index + 1
            taken[form_id].add(key)
            vals['key'] = key
        return super().create(vals_list)

    @api.constrains('field_type', 'options')
    def _check_options(self):
        for question in self:
            if question.field_type in CHOICE_TYPES and not question._ff_options():
                raise ValidationError(self.env._('"%s" needs at least one choice.', question.name))

    @api.constrains('visible_if_field_id')
    def _check_condition(self):
        for question in self:
            condition = question.visible_if_field_id
            if condition and (condition == question or condition.form_id != question.form_id):
                raise ValidationError(self.env._('"%s" can only depend on another question of the same form.', question.name))

    def _ff_options(self):
        return [line.strip() for line in (self.options or '').splitlines() if line.strip()]

    def _ff_is_visible(self, answers):
        condition = self.visible_if_field_id
        if not condition:
            return True
        actual = answers.get(condition.key)
        expected = (self.visible_if_value or '').strip().lower()
        if isinstance(actual, list):
            return expected in [str(a).strip().lower() for a in actual]
        if isinstance(actual, bool) or condition.field_type == 'checkbox':
            truthy = actual in (True, 'true', 'True', 1, '1', 'yes', 'Yes')
            return expected in ('yes', 'true', '1') if truthy else expected in ('no', 'false', '0')
        return str(actual if actual is not None else '').strip().lower() == expected

    @api.onchange('partner_field_id')
    def _onchange_partner_field(self):
        field = self.partner_field_id
        if not field:
            return
        self.field_type = PARTNER_FIELD_TYPES.get(field.ttype, self.field_type)
        if not self.name:
            self.name = field.field_description
        if field.ttype == 'selection':
            selection = self.env['res.partner']._fields[field.name]._description_selection(self.env)
            self.options = '\n'.join(label for _value, label in selection)

    def _ff_partner_value(self, partner):
        """The customer's current value, shaped like an answer; None when not linked or empty."""
        self.ensure_one()
        field = self.partner_field_id
        if not field or not partner or field.name not in partner._fields:
            return None
        value = partner.sudo()[field.name]
        if field.ttype == 'boolean':
            return bool(value)
        if value in (False, None, ''):
            return None
        if field.ttype == 'date':
            return value.isoformat()
        if field.ttype == 'selection':
            return dict(partner._fields[field.name]._description_selection(self.env)).get(value)
        if field.ttype == 'html':
            return re.sub(r'<[^>]+>', ' ', str(value)).strip() or None
        return value

    def _ff_partner_write_value(self, answer):
        """The answer converted for the customer field."""
        self.ensure_one()
        field = self.partner_field_id
        if field.ttype == 'selection':
            selection = self.env['res.partner']._fields[field.name]._description_selection(self.env)
            return next((value for value, label in selection if label == answer or value == answer), False)
        if field.ttype == 'boolean':
            return bool(answer)
        if field.ttype == 'integer':
            return int(float(answer))
        if field.ttype in ('float', 'monetary'):
            return float(answer)
        return answer

    def _ff_check_range(self, value):
        if self.min_value and value < self.min_value:
            raise ValueError(self.env._('must be at least %s', self.min_value))
        if self.max_value and value > self.max_value:
            raise ValueError(self.env._('must be at most %s', self.max_value))
        return value

    def _ff_clean(self, value):
        """Normalised answer, None when empty. Raises ValueError with a message."""
        kind = self.field_type
        if kind == 'checkbox':
            if value in (None, ''):
                return None
            return value in (True, 'true', 'True', 1, '1', 'yes', 'Yes')
        if value is None or value == '' or value == []:
            return None
        if kind in ('text', 'textarea', 'phone'):
            return str(value).strip()[:4000] or None
        if kind == 'email':
            text = str(value).strip()
            if '@' not in text or '.' not in text.split('@')[-1]:
                raise ValueError(self.env._('enter a valid email'))
            return text
        if kind == 'number':
            number = float(value)
            if not number.is_integer():
                raise ValueError(self.env._('enter a whole number'))
            return int(self._ff_check_range(number))
        if kind == 'decimal':
            return self._ff_check_range(float(value))
        if kind == 'rating':
            rating = int(float(value))
            if not 1 <= rating <= 5:
                raise ValueError(self.env._('choose 1 to 5'))
            return rating
        if kind == 'date':
            day = fields.Date.to_date(str(value)[:10])
            if not day:
                raise ValueError(self.env._('enter a date'))
            return day.isoformat()
        options = self._ff_options()
        if kind == 'select':
            if str(value) not in options:
                raise ValueError(self.env._('choose one of the options'))
            return str(value)
        if kind == 'multiselect':
            values = value if isinstance(value, list) else [value]
            values = [str(v) for v in values]
            if any(v not in options for v in values):
                raise ValueError(self.env._('choose from the options'))
            return values or None
        return value
