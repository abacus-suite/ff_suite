from datetime import timedelta

from odoo import api, fields, models
from odoo.exceptions import AccessError, UserError, ValidationError

MAX_PHOTOS = 3


def _strip_data_url(image):
    if isinstance(image, str) and image.startswith('data:') and ',' in image:
        return image.split(',', 1)[1]
    return image


def collection_limit(env, key, default):
    raw = env['ir.config_parameter'].sudo().get_param('ff_collections.%s' % key)
    try:
        return float(raw) if raw not in (None, False, '') else default
    except (TypeError, ValueError):
        return default


class FfCollection(models.Model):
    """Money collected from a customer in the field."""
    _name = 'ff.collection'
    _description = 'Field Collection'
    _inherit = ['mail.thread']
    _order = 'date desc, id desc'

    name = fields.Char(compute='_compute_name', store=True)
    employee_id = fields.Many2one('hr.employee', required=True, index=True, ondelete='cascade',
                                  default=lambda self: self.env.user.employee_id)
    team_id = fields.Many2one(related='employee_id.ff_team_id', store=True)
    department_id = fields.Many2one(related='employee_id.department_id', store=True)
    partner_id = fields.Many2one('res.partner', string='Contact', required=True, index=True)
    visit_id = fields.Many2one('ff.visit', string='Visit', ondelete='set null')
    date = fields.Datetime(required=True, default=fields.Datetime.now, index=True, tracking=True)
    mode_id = fields.Many2one('ff.collection.mode', string='Mode', required=True, tracking=True)
    mode_type = fields.Selection(related='mode_id.mode_type', store=True)
    amount = fields.Monetary(required=True, tracking=True)
    company_id = fields.Many2one(related='employee_id.company_id', store=True)
    currency_id = fields.Many2one(related='company_id.currency_id')
    reference = fields.Char(string='Reference / Cheque No.')
    instrument_date = fields.Date(string='Cheque Date')
    note = fields.Text()
    photo_count = fields.Integer(compute='_compute_photo_count')
    deposit_id = fields.Many2one('ff.collection.deposit', string='Deposit', ondelete='set null', index=True)
    state = fields.Selection([
        ('collected', 'With the employee'),
        ('submitted', 'Submitted to office'),
        ('received', 'Received by office'),
        ('cancelled', 'Cancelled'),
    ], default='collected', required=True, index=True, tracking=True)
    latitude = fields.Float(digits=(10, 7))
    longitude = fields.Float(digits=(10, 7))
    client_uuid = fields.Char(index=True, copy=False)

    _client_uuid_uniq = models.Constraint('UNIQUE(client_uuid)', 'This collection was already received.')

    @api.depends('partner_id', 'date', 'amount')
    def _compute_name(self):
        for collection in self:
            collection.name = '%s - %s' % (collection.partner_id.name or '', collection.amount)

    def _compute_photo_count(self):
        counts = dict(self.env['ir.attachment'].sudo()._read_group(
            [('res_model', '=', self._name), ('res_id', 'in', self.ids)], ['res_id'], ['__count']))
        for collection in self:
            collection.photo_count = counts.get(collection.id, 0)

    @api.constrains('amount', 'mode_id')
    def _check_amount(self):
        for collection in self:
            if collection.amount <= 0:
                raise ValidationError(self.env._('The collected amount must be more than zero.'))
            limit = collection.mode_id.max_amount
            if limit and collection.amount > limit:
                raise ValidationError(self.env._(
                    'The maximum for "%(mode)s" is %(limit)s.', mode=collection.mode_id.name, limit=limit))

    # ------------------------------------------------------------------
    # Pending money and the check-in block
    # ------------------------------------------------------------------
    @api.model
    def _ff_pending(self, employee):
        """Collections still with the employee that must be deposited."""
        return self.sudo().search([
            ('employee_id', '=', employee.id),
            ('state', '=', 'collected'),
            ('mode_id.needs_deposit', '=', True),
        ])

    @api.model
    def ff_pending_status(self, employee):
        """Pending money and whether it is over the office limits."""
        pending = self._ff_pending(employee)
        max_days = int(collection_limit(self.env, 'max_days', 3))
        max_amount = collection_limit(self.env, 'max_amount', 0.0)
        total = sum(pending.mapped('amount'))
        oldest = min(pending.mapped('date'), default=False)
        overdue_days = 0
        if oldest:
            overdue_days = (fields.Datetime.now() - oldest).days
        over_days = bool(max_days and oldest and overdue_days >= max_days)
        over_amount = bool(max_amount and total > max_amount)
        return {
            'count': len(pending),
            'amount': total,
            'currency': pending[:1].currency_id.name or employee.company_id.currency_id.name,
            'oldest_date': oldest,
            'days_held': overdue_days,
            'max_days': max_days,
            'max_amount': max_amount,
            'over_days': over_days,
            'over_amount': over_amount,
            'blocked': over_days or over_amount,
        }

    @api.model
    def _ff_check_deposit_due(self, employee):
        """Raise when the employee must hand over money before visiting again."""
        status = self.ff_pending_status(employee)
        if not status['blocked']:
            return
        if status['over_amount']:
            raise UserError(self.env._(
                'Please submit your cash to the office. You are holding %(amount)s, above the limit of %(limit)s.',
                amount=status['amount'], limit=status['max_amount']))
        raise UserError(self.env._(
            'Please submit your cash to the office. %(amount)s has been with you for %(days)s days '
            '(limit %(limit)s days).',
            amount=status['amount'], days=status['days_held'], limit=status['max_days']))

    # ------------------------------------------------------------------
    # Mobile app
    # ------------------------------------------------------------------
    @api.model
    def ff_create_from_app(self, employee, data):
        Collection = self.sudo()
        uuid = data.get('uuid') or False
        if uuid:
            existing = Collection.search([('client_uuid', '=', uuid)], limit=1)
            if existing:
                return existing
        modes = self.env['ff.collection.mode'].ff_for_employee(employee)
        mode = modes.filtered(lambda m: str(m.id) == str(data.get('mode_id')))
        if not mode:
            raise UserError(self.env._('Choose a collection mode you have access to.'))
        try:
            amount = float(data.get('amount'))
        except (TypeError, ValueError):
            raise UserError(self.env._('Enter the collected amount.'))
        reference = (data.get('reference') or '').strip()
        if mode.requires_reference and not reference:
            raise UserError(self.env._('A reference is required for "%s".', mode.name))
        photos = [p for p in (data.get('photos') or []) if isinstance(p, str) and p][:MAX_PHOTOS]
        if mode.requires_photo and not photos:
            raise UserError(self.env._('A photo is required for "%s".', mode.name))
        instrument_date = fields.Date.to_date(data.get('instrument_date')) if data.get('instrument_date') else False
        if mode.requires_instrument_date and not instrument_date:
            raise UserError(self.env._('Give the cheque date for "%s".', mode.name))

        partner = self.env['res.partner'].sudo().browse(int(data['partner_id'])).exists() \
            if str(data.get('partner_id') or '').isdigit() else self.env['res.partner']
        if not partner:
            raise UserError(self.env._('Choose the contact who paid.'))
        visit = self.env['ff.visit'].sudo().browse(int(data['visit_id'])).exists() \
            if str(data.get('visit_id') or '').isdigit() else self.env['ff.visit']
        if visit and visit.employee_id != employee:
            raise AccessError(self.env._('This visit is not yours.'))

        collection = Collection.create({
            'employee_id': employee.id,
            'partner_id': partner.id,
            'visit_id': visit.id or False,
            'mode_id': mode.id,
            'amount': amount,
            'reference': reference or False,
            'instrument_date': instrument_date,
            'note': (data.get('note') or '').strip() or False,
            'latitude': data.get('lat') or 0.0,
            'longitude': data.get('lng') or 0.0,
            'client_uuid': uuid,
            'state': 'collected' if mode.needs_deposit else 'received',
        })
        if photos:
            self.env['ir.attachment'].sudo().create([{
                'name': 'collection_%s_%s.jpg' % (collection.id, index + 1),
                'datas': _strip_data_url(photo),
                'res_model': self._name,
                'res_id': collection.id,
                'mimetype': 'image/jpeg',
            } for index, photo in enumerate(photos)])
        return collection

    def action_cancel(self):
        for collection in self:
            if collection.state == 'received':
                raise UserError(self.env._('Money already received by the office cannot be cancelled here.'))
            collection.state = 'cancelled'


class FfCollectionDepositReminder(models.AbstractModel):
    """Daily reminder for money kept too long by field staff."""
    _name = 'ff.collection.reminder'
    _description = 'Collection Deposit Reminder'

    @api.model
    def _cron_remind(self):
        Collection = self.env['ff.collection'].sudo()
        max_days = int(collection_limit(self.env, 'max_days', 3))
        if not max_days:
            return
        limit = fields.Datetime.now() - timedelta(days=max_days)
        overdue = Collection.search([('state', '=', 'collected'), ('mode_id.needs_deposit', '=', True),
                                     ('date', '<', limit)])
        for employee in overdue.employee_id:
            manager_user = employee.parent_id.user_id
            employee_lines = overdue.filtered(lambda c, e=employee: c.employee_id == e)
            if manager_user:
                employee_lines[:1].activity_schedule(
                    'mail.mail_activity_data_todo', user_id=manager_user.id,
                    summary=self.env._('%(name)s is holding %(amount)s in collections',
                                       name=employee.name, amount=sum(employee_lines.mapped('amount'))))
