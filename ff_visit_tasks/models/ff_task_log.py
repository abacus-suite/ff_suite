"""A task the field has done, and everything it set going.

The app walks the salesperson through a task one screen at a time and sends it
as a single submission at the end, so it can be queued on a phone without a
signal. This is where that submission lands: one record per task, the answers on
it, and the stock counts, demands, notes and plans it caused made in the same
breath, so that none of them can exist without the other.
"""
from odoo import api, fields, models
from odoo.exceptions import UserError

VISIT_OUTCOMES = [('successful', 'Successful'), ('closed', 'Outlet Closed'), ('others', 'Others')]
MEETING_RESULTS = [('met', 'Met the client'), ('not_available', 'Client not available'), ('others', 'Others')]
PERSON_MET = [('owner', 'Owner'), ('sales_manager', 'Sales Manager'), ('staff', 'Staff'), ('others', 'Others')]
LEAD_OUTCOMES = [('follow_up', 'Follow up'), ('onboarded', 'Onboarded'), ('not_interested', 'Not Interested')]
FREE_REASONS = [('samples', 'Samples'), ('fizz_test', 'Fizz Test'), ('other', 'Other')]
DAMAGE_REASONS = [('expired', 'Expired'), ('damaged', 'Damaged')]
SAMPLE_SOURCES = [('distributor', 'Distributor'), ('outlet', 'Outlet'), ('company', 'Company')]
OUTLET_CATEGORIES = [('modern_trade', 'Modern Trade'), ('general_trade', 'General Trade'), ('hotel', 'Hotel'),
                     ('cafe', 'Café'), ('restaurant', 'Restaurant'), ('others', 'Others')]
# What each answer is called on the visit, which has a shorter list of its own.
VISIT_OUTCOME_CODES = {'successful': 'met', 'closed': 'closed', 'others': 'other',
                       'met': 'met', 'not_available': 'not_available'}


class FfTaskLog(models.Model):
    _name = 'ff.task.log'
    _description = 'Field Task'
    _inherit = ['mail.thread']
    _order = 'date desc, id desc'

    name = fields.Char(default=lambda self: self.env._('New'), copy=False, readonly=True)
    task_type_id = fields.Many2one('ff.task.type', string='Task', required=True, index=True, tracking=True)
    task_code = fields.Selection(related='task_type_id.code', store=True, index=True)
    employee_id = fields.Many2one('hr.employee', required=True, index=True, ondelete='cascade', tracking=True)
    team_id = fields.Many2one(related='employee_id.ff_team_id', store=True)
    partner_id = fields.Many2one('res.partner', string='Contact', index=True,
                                 help='The outlet or lead. Empty for a task done on the road.')
    visit_id = fields.Many2one('ff.visit', string='Visit', ondelete='set null', index=True)
    date = fields.Datetime(required=True, default=fields.Datetime.now, index=True)
    day = fields.Date(compute='_compute_day', store=True, index=True)
    latitude = fields.Float(digits=(10, 7))
    longitude = fields.Float(digits=(10, 7))
    company_id = fields.Many2one(related='employee_id.company_id', store=True)
    client_uuid = fields.Char(index=True, copy=False)
    photo_count = fields.Integer(compute='_compute_photo_count')

    # Client visit
    outlet_open = fields.Boolean(string='Outlet Open')
    visit_outcome = fields.Selection(VISIT_OUTCOMES, string='Visit Outcome', index=True)
    demand_wanted = fields.Boolean(string='New Demand')
    demand_reason = fields.Text(string='Why No Demand')
    free_reason = fields.Selection(FREE_REASONS)
    free_note = fields.Char(string='Free Reason Note')
    ledger_sent = fields.Boolean(string='Ledger Sent')
    outstanding = fields.Float(string='Outstanding at Visit', digits=(16, 2))
    damage_any = fields.Boolean(string='Damaged / Expired')
    damage_reason = fields.Selection(DAMAGE_REASONS)
    # Leads
    outlet_category = fields.Selection(OUTLET_CATEGORIES)
    outlet_category_note = fields.Char()
    person_met = fields.Selection(PERSON_MET)
    person_note = fields.Char()
    samples_given = fields.Boolean(string='Samples Given')
    samples_reason = fields.Char(string='Why No Samples')
    margin_note = fields.Text(string='Margin Discussed')
    meeting_update = fields.Text()
    lead_outcome = fields.Selection(LEAD_OUTCOMES, index=True)
    follow_up_date = fields.Date(index=True)
    not_interested_reason = fields.Char()
    meeting_result = fields.Selection(MEETING_RESULTS)
    # Adhoc, samples and material
    description = fields.Text()
    sample_source = fields.Selection(SAMPLE_SOURCES)
    distributor_id = fields.Many2one('res.partner', string='Distributor', domain=[('ff_is_distributor', '=', True)])
    outcome_note = fields.Text(string='Note')

    line_ids = fields.One2many('ff.task.log.line', 'log_id', string='Quantities')
    demand_ids = fields.Many2many('ff.demand', 'ff_task_log_demand_rel', 'log_id', 'demand_id', string='Demands')
    note_ids = fields.One2many('ff.distributor.note', 'task_log_id', string='Credit / Debit Notes')
    onboard = fields.Boolean(readonly=True, help='Asked for the outlet to be onboarded.')

    _client_uuid_uniq = models.Constraint('UNIQUE(client_uuid)', 'This task was already received.')

    @api.depends('date')
    def _compute_day(self):
        for log in self:
            log.day = log.employee_id._ff_to_local(log.date).date() if log.date and log.employee_id else False

    def _compute_photo_count(self):
        counts = dict(self.env['ir.attachment'].sudo()._read_group(
            [('res_model', '=', self._name), ('res_id', 'in', self.ids)], ['res_id'], ['__count']))
        for log in self:
            log.photo_count = counts.get(log.id, 0)

    @api.depends('name', 'task_type_id', 'partner_id')
    def _compute_display_name(self):
        for log in self:
            log.display_name = '%s - %s' % (log.task_type_id.name or '', log.partner_id.name or log.name)

    @api.model_create_multi
    def create(self, vals_list):
        for vals in vals_list:
            if vals.get('name', self.env._('New')) == self.env._('New'):
                vals['name'] = self.env['ir.sequence'].sudo().next_by_code('ff.task.log') or '/'
        return super().create(vals_list)

    def action_open_photos(self):
        self.ensure_one()
        return {
            'type': 'ir.actions.act_window', 'name': self.env._('Photos'), 'res_model': 'ir.attachment',
            'view_mode': 'kanban,list,form',
            'domain': [('res_model', '=', self._name), ('res_id', '=', self.id)],
        }

    # ------------------------------------------------------------------
    # The submission
    # ------------------------------------------------------------------
    @api.model
    def ff_submit_from_app(self, employee, data):
        """Record one finished task and everything it set going."""
        Log = self.sudo()
        uuid = data.get('uuid') or False
        if uuid:
            existing = Log.search([('client_uuid', '=', uuid)], limit=1)
            if existing:
                return existing
        task_type = self.env['ff.task.type'].sudo().search([('code', '=', data.get('task'))], limit=1)
        if not task_type:
            raise UserError(self.env._('Unknown task.'))

        partner = self.env['res.partner'].sudo().browse(int(data.get('partner_id') or 0)).exists()
        visit = self._ff_open_visit(employee, partner, data)
        handler = getattr(self, '_ff_task_%s' % task_type.code)

        log = Log.create({
            'task_type_id': task_type.id,
            'employee_id': employee.id,
            'partner_id': partner.id or False,
            'visit_id': visit.id or False,
            'date': fields.Datetime.now(),
            'latitude': float(data.get('lat') or 0.0),
            'longitude': float(data.get('lng') or 0.0),
            'client_uuid': uuid,
        })
        made = handler(log, employee, partner, visit, data)
        # A new lead is visited the moment it exists, so its visit is made here.
        if made is not None and made:
            visit = made
            log.visit_id = visit.id
        self._ff_attach(log, data.get('photos'))
        self._ff_finish_visit(log, visit, data)
        return log

    @api.model
    def _ff_open_visit(self, employee, partner, data):
        Visit = self.env['ff.visit'].sudo()
        visit = Visit.browse(int(data.get('visit_id') or 0)).exists() if data.get('visit_id') else Visit
        if not visit and partner:
            visit = Visit.search([('employee_id', '=', employee.id), ('partner_id', '=', partner.id),
                                  ('state', '=', 'ongoing')], limit=1)
        return visit if visit.employee_id == employee else Visit

    @api.model
    def _ff_finish_visit(self, log, visit, data):
        """Submitting the last step is checking out."""
        if not visit or visit.state != 'ongoing':
            return
        code = log.visit_outcome or log.meeting_result or 'others'
        # The visit's own outcomes can ask for a note or a photo - "Shop closed" wants
        # a photo - and the task has already collected both, so they are handed over
        # rather than asked for a second time.
        photos = [p.get('data') if isinstance(p, dict) else p for p in data.get('photos') or []]
        photos = [p for p in photos if isinstance(p, str) and p]
        visit.sudo().ff_check_out({
            'lat': log.latitude, 'lng': log.longitude, 'task': True,
            'outcome': VISIT_OUTCOME_CODES.get(code, 'other'),
            'note': log.outcome_note or self.env._('Recorded in task %s.', log.name),
            'photos': photos[:3],
            'device_time': data.get('at'),
        })

    @api.model
    def _ff_attach(self, log, photos):
        Attachment = self.env['ir.attachment'].sudo()
        vals = []
        for index, photo in enumerate(photos or []):
            raw = photo.get('data') if isinstance(photo, dict) else photo
            if not isinstance(raw, str) or not raw:
                continue
            if raw.startswith('data:') and ',' in raw:
                raw = raw.split(',', 1)[1]
            tag = (photo.get('tag') if isinstance(photo, dict) else None) or 'photo'
            vals.append({
                'name': '%s_%s_%s.jpg' % (log.name.replace('/', '-'), tag, index + 1),
                'datas': raw, 'res_model': self._name, 'res_id': log.id, 'mimetype': 'image/jpeg',
            })
        if vals:
            Attachment.create(vals)

    # ------------------------------------------------------------------
    # Helpers shared by the tasks
    # ------------------------------------------------------------------
    @api.model
    def _ff_lines(self, log, kind, rows, reason=None):
        lines = []
        for row in rows or []:
            try:
                quantity = float(row.get('qty') if 'qty' in row else row.get('quantity') or 0)
            except (TypeError, ValueError):
                continue
            product = self.env['product.product'].sudo().browse(int(row.get('product_id') or 0)).exists()
            if product and quantity > 0 or (kind == 'stock' and product):
                lines.append((0, 0, {'kind': kind, 'product_id': product.id, 'quantity': quantity,
                                     'note': reason or False}))
        if lines:
            log.write({'line_ids': lines})
        return [row for row in rows or [] if float(row.get('qty') or row.get('quantity') or 0) > 0]

    @api.model
    def _ff_require(self, ok, message):
        if not ok:
            raise UserError(self.env._(message))

    @api.model
    def _ff_make_demand(self, employee, partner, visit, order_rows, free_rows, note, free_reason=None):
        """Raise the demand: what the outlet ordered, and what it was given free."""
        Product = self.env['product.product'].sudo()
        lines = []
        for row in order_rows:
            product = Product.browse(int(row['product_id'])).exists()
            if product:
                lines.append((0, 0, {'product_id': product.id, 'quantity': float(row['qty']),
                                     'price_unit': product.ff_field_price()}))
        Line = self.env['ff.demand.line']
        for row in free_rows:
            product = Product.browse(int(row['product_id'])).exists()
            if product:
                values = {'product_id': product.id, 'quantity': float(row['qty']), 'price_unit': 0.0}
                if 'is_foc' in Line._fields:
                    values.update(is_foc=True, foc_reason=free_reason or False)
                lines.append((0, 0, values))
        if not lines:
            return self.env['ff.demand']
        return self.env['ff.demand'].sudo().create({
            'employee_id': employee.id, 'partner_id': partner.id, 'visit_id': visit.id or False,
            'line_ids': lines, 'note': note or False,
            'latitude': visit.check_in_lat if visit else 0.0, 'longitude': visit.check_in_lng if visit else 0.0,
        })

    @api.model
    def _ff_demand_block(self, log, employee, partner, visit, block):
        """Order quantity and free quantity, which are kept apart on the form."""
        block = block or {}
        wanted = bool(block.get('wanted'))
        log.demand_wanted = wanted
        if not wanted:
            reason = (block.get('reason') or '').strip()
            self._ff_require(reason, 'Say why no demand was taken.')
            log.demand_reason = reason
            return
        order = self._ff_lines(log, 'order', block.get('order'))
        free = self._ff_lines(log, 'free', block.get('free'))
        self._ff_require(order or free, 'Enter the quantity ordered, or the free quantity.')
        if free:
            reason = block.get('free_reason')
            self._ff_require(reason in dict(FREE_REASONS), 'Say why the quantity is free.')
            note = (block.get('free_note') or '').strip()
            self._ff_require(reason != 'other' or note, 'Describe the free reason.')
            log.write({'free_reason': reason, 'free_note': note or False})
        demand = self._ff_make_demand(employee, partner, visit, order, free, log.name,
                                      free_reason=log.free_reason)
        if demand:
            log.demand_ids = [(4, demand.id)]

    # ------------------------------------------------------------------
    # 1. Client visit
    # ------------------------------------------------------------------
    @api.model
    def _ff_task_client_visit(self, log, employee, partner, visit, data):
        self._ff_require(partner, 'Choose the outlet.')
        is_open = bool(data.get('open'))
        log.outlet_open = is_open
        ledger = data.get('ledger') or {}
        log.write({'ledger_sent': bool(ledger.get('sent')),
                   'outstanding': float(ledger.get('outstanding') or 0.0)})
        if log.outstanding > 0:
            self._ff_require(log.ledger_sent, 'Send the ledger to the outlet before finishing.')

        if not is_open:
            # Only the photo and the ledger are asked for; the rest is not applicable.
            log.write({'visit_outcome': 'closed', 'outcome_note': data.get('outcome_note') or False})
            return

        stock = data.get('stock') or []
        self._ff_require(stock, 'Enter the closing stock.')
        self._ff_lines(log, 'stock', stock)
        if 'ff.stock.count' in self.env:
            self.env['ff.stock.count'].ff_record(
                employee, partner, [{'product_id': r['product_id'], 'quantity': r.get('qty') or 0} for r in stock],
                visit=visit or None, note=log.name)

        self._ff_demand_block(log, employee, partner, visit, data.get('demand'))
        self.env['ff.partner.material'].ff_record_check(partner, data.get('materials'))

        damage = data.get('damage') or {}
        log.damage_any = bool(damage.get('any'))
        if log.damage_any:
            reason = damage.get('reason')
            self._ff_require(reason in dict(DAMAGE_REASONS), 'Say whether the bottles were expired or damaged.')
            rows = self._ff_lines(log, 'credit', damage.get('lines'), reason)
            self._ff_require(rows, 'Enter the quantity of damaged or expired bottles.')
            log.damage_reason = reason
            self.env['ff.distributor.note'].ff_raise(
                employee, 'credit', rows, distributor=partner.ff_distributor_id, partner=partner,
                reason=dict(DAMAGE_REASONS)[reason], task_log=log)

        outcome = data.get('outcome')
        self._ff_require(outcome in ('successful', 'others'), 'Say how the visit went.')
        note = (data.get('outcome_note') or '').strip()
        self._ff_require(outcome != 'others' or note, 'Describe how the visit went.')
        log.write({'visit_outcome': outcome, 'outcome_note': note or False})

    # ------------------------------------------------------------------
    # 2 and 3. New lead, and following one up
    # ------------------------------------------------------------------
    @api.model
    def _ff_create_lead(self, employee, data):
        contact = data.get('contact') or {}
        name = (contact.get('name') or '').strip()
        self._ff_require(name, 'Give the outlet a name.')
        Partner = self.env['res.partner']
        category = self.env.ref('ff_clients.contact_category_lead')
        district = self.env['ff.district'].sudo().browse(int(contact.get('district_id') or 0)).exists()
        vals = {
            'name': name, 'ff_category_id': category.id,
            'partner_latitude': float(data.get('lat') or 0.0),
            'partner_longitude': float(data.get('lng') or 0.0),
            'ff_district_id': district.id or False,
            'phone': contact.get('phone') or False, 'street': contact.get('street') or False,
            'comment': (contact.get('note') or '').strip() or False,
        }
        route = self.env['ff.beat'].sudo().browse(int(contact.get('beat_id') or 0)).exists()
        if route:
            vals['ff_route_ids'] = [(4, route.id)]
            vals['ff_extra_employee_ids'] = route.employee_ids.ids
        # Fields that belong to the customer-fields module, set only where it is installed.
        fields_ = Partner._fields
        if 'client_prospect' in fields_:
            vals['client_prospect'] = 'prospect'
        if 'client_status' in fields_:
            vals['client_status'] = 'new_lead'
        if 'x_studio_territory' in fields_ and contact.get('territory'):
            vals['x_studio_territory'] = contact['territory']
        if 'business_category_id' in fields_ and contact.get('category') in dict(OUTLET_CATEGORIES):
            label = dict(OUTLET_CATEGORIES)[contact['category']]
            match = self.env['business.category'].sudo().search([('name', '=ilike', label)], limit=1)
            if match:
                vals['business_category_id'] = match.id
        return Partner.ff_create_from_app(employee, vals)

    @api.model
    def _ff_task_new_lead(self, log, employee, partner, visit, data):
        contact = data.get('contact') or {}
        category = contact.get('category')
        self._ff_require(category in dict(OUTLET_CATEGORIES), 'Choose the outlet category.')
        note = (contact.get('category_note') or '').strip()
        self._ff_require(category != 'others' or note, 'Describe the outlet category.')
        self._ff_require(contact.get('beat_id'), 'Choose the beat.')
        self._ff_require(contact.get('district_id'), 'Choose the territory.')
        lead = self._ff_create_lead(employee, data)
        log.write({'partner_id': lead.id, 'outlet_category': category, 'outlet_category_note': note or False})
        # The lead did not exist when the salesperson walked in, so it could not
        # be checked in to. It is, now: the visit starts and ends with this task.
        made = self.env['ff.visit']
        try:
            with self.env.cr.savepoint():
                made = self.env['ff.visit'].ff_check_in(employee, lead, {
                    'lat': data.get('lat'), 'lng': data.get('lng'), 'accuracy': data.get('accuracy'),
                    'task': 'new_lead', 'offsite': True,
                })
        except Exception:
            made = self.env['ff.visit']
        self._ff_meeting(log, employee, lead, made or visit, data)
        return made

    @api.model
    def _ff_task_lead_follow_up(self, log, employee, partner, visit, data):
        self._ff_require(partner, 'Choose the lead.')
        self._ff_meeting(log, employee, partner, visit, data)

    @api.model
    def _ff_meeting(self, log, employee, partner, visit, data):
        """Steps 2 to 7: who was met, samples, margin, the meeting and where it goes next."""
        person = data.get('person') or {}
        self._ff_require(person.get('designation') in dict(PERSON_MET), 'Say who was met.')
        person_note = (person.get('note') or '').strip()
        self._ff_require(person['designation'] != 'others' or person_note, 'Describe who was met.')

        samples = data.get('samples') or {}
        given = bool(samples.get('given'))
        log.write({'person_met': person['designation'], 'person_note': person_note or False,
                   'samples_given': given})
        if given:
            rows = self._ff_lines(log, 'sample', samples.get('lines'))
            self._ff_require(rows, 'Enter the quantity of samples given.')
        else:
            reason = (samples.get('reason') or '').strip()
            self._ff_require(reason, 'Say why no samples were given.')
            log.samples_reason = reason

        margin = (data.get('margin') or '').strip()
        update = (data.get('meeting_update') or '').strip()
        self._ff_require(margin, 'Describe the margin discussed.')
        self._ff_require(update, 'Describe the meeting.')
        log.write({'margin_note': margin, 'meeting_update': update})

        result = data.get('result') or {}
        self._ff_require(result.get('code') in dict(MEETING_RESULTS), 'Say how it went.')
        result_note = (result.get('note') or '').strip()
        self._ff_require(result['code'] != 'others' or result_note, 'Describe how it went.')
        log.write({'meeting_result': result['code'], 'outcome_note': result_note or False})

        outcome = data.get('outcome') or {}
        code = outcome.get('code')
        self._ff_require(code in dict(LEAD_OUTCOMES), 'Choose the outcome.')
        log.lead_outcome = code
        Plan = self.env['ff.beat.plan']
        Partner = self.env['res.partner'].sudo()
        if code == 'follow_up':
            date = fields.Date.to_date(outcome.get('follow_up_date'))
            self._ff_require(date, 'Enter the follow-up date.')
            log.follow_up_date = date
            Plan.ff_add_customer(employee, partner, date)
        elif code == 'not_interested':
            reason = (outcome.get('reason') or '').strip()
            self._ff_require(reason, 'Say why the lead is not interested.')
            log.not_interested_reason = reason
            Plan.ff_remove_customer(employee, partner)
            if 'client_status' in Partner._fields:
                partner.sudo().client_status = 'not_interested'
        else:
            log.onboard = True
            if 'client_status' in Partner._fields:
                partner.sudo().client_status = 'confirmed'

    @api.model
    def ff_leads_due(self, employee):
        """Leads waiting for a follow-up, most overdue first.

        Read off the last meeting held with each lead: a lead is due when that
        meeting ended in "follow up" and the date it set has come or is coming.
        """
        today = employee._ff_today()
        logs = self.sudo().search([
            ('task_code', 'in', ('new_lead', 'lead_follow_up')),
            ('employee_id', 'in', (employee | employee._ff_subordinates()).ids),
            ('partner_id', '!=', False)], order='date desc')
        latest = {}
        for log in logs:
            latest.setdefault(log.partner_id.id, log)
        rows = []
        for log in latest.values():
            if log.lead_outcome != 'follow_up' or not log.follow_up_date:
                continue
            days = (log.follow_up_date - today).days
            rows.append({
                'partner': log.partner_id, 'date': log.follow_up_date,
                'status': 'overdue' if days < 0 else ('today' if days == 0 else 'upcoming'),
                'days': days,
            })
        rows.sort(key=lambda r: r['date'])
        return rows

    # ------------------------------------------------------------------
    # 4. Adhoc
    # ------------------------------------------------------------------
    @api.model
    def _ff_task_adhoc(self, log, employee, partner, visit, data):
        description = (data.get('description') or '').strip()
        self._ff_require(description, 'Describe what was done.')
        self._ff_require(data.get('photos'), 'Take the photo.')
        log.description = description

    # ------------------------------------------------------------------
    # 5. Sample collection
    # ------------------------------------------------------------------
    @api.model
    def _ff_task_sample_collection(self, log, employee, partner, visit, data):
        source = data.get('source')
        self._ff_require(source in dict(SAMPLE_SOURCES), 'Say where the samples were collected from.')
        log.sample_source = source
        rows = self._ff_lines(log, 'sample', data.get('lines'))
        self._ff_require(rows, 'Enter the quantity of each flavour.')
        reason = (data.get('reason') or '').strip()
        self._ff_require(reason, 'Give the reason.')
        log.description = reason
        Product = self.env['product.product']

        if source == 'distributor':
            distributor = self.env['res.partner'].sudo().browse(int(data.get('distributor_id') or 0)).exists()
            self._ff_require(distributor, 'Choose the distributor.')
            log.distributor_id = distributor.id
            # Their stock was given away, so they are not to pay the company for it.
            self.env['ff.distributor.note'].ff_raise(
                employee, 'debit', rows, distributor=distributor, reason=reason, task_log=log)
        elif source == 'outlet':
            # The outlet the samples come from is not necessarily the one being visited:
            # the person may be standing at a new shop with samples taken from a
            # neighbour. The visit keeps its own contact; the source is named apart.
            source_outlet = self.env['res.partner'].sudo().browse(
                int(data.get('source_partner_id') or 0)).exists() or partner
            self._ff_require(source_outlet, 'Choose the outlet the samples come from.')
            partner = source_outlet
            distributor = partner.ff_distributor_id
            log.distributor_id = distributor.id or False
            # The outlet gives the samples away from its own shelf, so it is made
            # good with the same pieces free, supplied by its distributor - who
            # in turn is not to pay the company for them.
            demand = self._ff_make_demand(employee, partner, visit, [], rows, log.name, free_reason=reason)
            if demand:
                log.demand_ids = [(4, demand.id)]
            self.env['ff.distributor.note'].ff_raise(
                employee, 'debit', rows, distributor=distributor or None, partner=partner,
                reason=reason, task_log=log, demand=demand or None)
        else:
            self._ff_require(employee.ff_team_id.ff_company_samples,
                             'Your team cannot take samples from company stock.')
            # An internal stock issue: the log is the record; nothing to bill or demand.

    # ------------------------------------------------------------------
    # 6. Marketing material supply
    # ------------------------------------------------------------------
    @api.model
    def _ff_task_marketing_supply(self, log, employee, partner, visit, data):
        self._ff_require(partner, 'Choose the outlet.')
        rows = self._ff_lines(log, 'supply', data.get('materials'))
        self._ff_require(rows, 'Enter the material supplied.')
        self._ff_require(data.get('photos'), 'Take the photo of the material supplied.')
        self.env['ff.partner.material'].ff_record_supply(partner, rows)


class FfTaskLogLine(models.Model):
    _name = 'ff.task.log.line'
    _description = 'Task Quantity'
    _order = 'log_id, kind, id'

    log_id = fields.Many2one('ff.task.log', required=True, ondelete='cascade', index=True)
    kind = fields.Selection([
        ('stock', 'Closing Stock'), ('order', 'Order'), ('free', 'Free'), ('credit', 'Credit Note'),
        ('sample', 'Sample'), ('supply', 'Supplied'),
    ], required=True, index=True)
    product_id = fields.Many2one('product.product', required=True, index=True)
    quantity = fields.Float(digits=(16, 2))
    note = fields.Char()
    task_code = fields.Selection(related='log_id.task_code', store=True)
    employee_id = fields.Many2one(related='log_id.employee_id', store=True)
    partner_id = fields.Many2one(related='log_id.partner_id', store=True)
    date = fields.Datetime(related='log_id.date', store=True)
