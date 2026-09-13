from datetime import timedelta

from odoo import api, fields, models
from odoo.exceptions import UserError

from odoo.addons.ff_base.tools import get_settings, haversine_m

OUTCOMES = [
    ('met', 'Met client'),
    ('order', 'Order taken'),
    ('not_available', 'Client not available'),
    ('closed', 'Shop closed'),
    ('other', 'Other'),
]
MAX_PHOTOS = 5
AUTO_CLOSE_HOURS = 10


def _num(value):
    try:
        return float(value)
    except (TypeError, ValueError):
        return None


def _strip_data_url(image):
    if isinstance(image, str) and image.startswith('data:') and ',' in image:
        return image.split(',', 1)[1]
    return image


class OffsiteConfirmation(Exception):
    """Check-in away from the client that the person has not yet confirmed as offsite."""

    def __init__(self, distance, radius, client):
        super().__init__(distance)
        self.distance, self.radius, self.client = distance, radius, client


class FfVisit(models.Model):
    _name = 'ff.visit'
    _description = 'Client Visit'
    _inherit = ['mail.thread']
    _order = 'check_in_at desc, id desc'

    employee_id = fields.Many2one('hr.employee', required=True, index=True, ondelete='cascade')
    team_id = fields.Many2one(related='employee_id.ff_team_id', store=True)
    partner_id = fields.Many2one('res.partner', string='Client', required=True, index=True, ondelete='restrict')
    state = fields.Selection([('ongoing', 'At Client'), ('done', 'Done')], default='ongoing', required=True, index=True)
    check_in_at = fields.Datetime(string='Check-in', required=True, default=fields.Datetime.now)
    check_out_at = fields.Datetime(string='Check-out')
    duration_min = fields.Integer(string='Duration (min)', compute='_compute_duration', store=True)
    check_in_lat = fields.Float(digits=(10, 7))
    check_in_lng = fields.Float(digits=(10, 7))
    check_in_accuracy = fields.Float(string='Accuracy (m)')
    check_in_mock = fields.Boolean(string='Mock Location')
    check_out_lat = fields.Float(digits=(10, 7))
    check_out_lng = fields.Float(digits=(10, 7))
    distance_m = fields.Integer(string='Distance from Client (m)')
    inside_geofence = fields.Boolean(string='At Client Location', default=True)
    location_captured = fields.Boolean(help='The client had no GPS location; it was saved from this check-in.')
    visit_type = fields.Selection([('onsite', 'Onsite'), ('offsite', 'Offsite')], default='onsite',
                                  required=True, index=True, tracking=True,
                                  help='Offsite: checked in away from the client, after confirming it in the app.')
    offsite_reason = fields.Char()
    outcome = fields.Selection(OUTCOMES, string='Outcome Code')
    outcome_id = fields.Many2one('ff.visit.outcome', string='Outcome', index=True)
    productive = fields.Boolean(related='outcome_id.productive', store=True)
    note = fields.Text()
    photo_count = fields.Integer(compute='_compute_photo_count')
    client_uuid = fields.Char(index=True, copy=False)

    _client_uuid_uniq = models.Constraint('UNIQUE(client_uuid)', 'This visit was already received.')

    @api.depends('check_in_at', 'check_out_at')
    def _compute_duration(self):
        for visit in self:
            visit.duration_min = int((visit.check_out_at - visit.check_in_at).total_seconds() // 60) \
                if visit.check_in_at and visit.check_out_at else 0

    def _compute_photo_count(self):
        counts = dict(self.env['ir.attachment'].sudo()._read_group(
            [('res_model', '=', self._name), ('res_id', 'in', self.ids)], ['res_id'], ['__count']))
        for visit in self:
            visit.photo_count = counts.get(visit.id, 0)

    @api.depends('partner_id', 'check_in_at')
    def _compute_display_name(self):
        for visit in self:
            visit.display_name = '%s - %s' % (visit.partner_id.name or '', visit.check_in_at or '')

    @api.model
    def ff_check_in(self, employee, partner, data):
        """Start a visit of ``employee`` at ``partner`` from the mobile app."""
        Visit = self.sudo()
        uuid = data.get('uuid') or False
        if uuid:
            existing = Visit.search([('client_uuid', '=', uuid)], limit=1)
            if existing:
                return existing
        ongoing = Visit.search([('employee_id', '=', employee.id), ('state', '=', 'ongoing')], limit=1)
        if ongoing:
            if ongoing.partner_id == partner:
                return ongoing
            raise UserError(self.env._('Check out from %s first.', ongoing.partner_id.display_name))

        lat, lng = _num(data.get('lat')), _num(data.get('lng'))
        if lat is None or lng is None:
            raise UserError(self.env._('Location is required to check in.'))
        settings = get_settings(self.env)
        is_mock = bool(data.get('mock'))
        if is_mock and not settings['allow_mock']:
            self.env['ff.compliance.log'].ff_log(employee, [{'type': 'mock_location', 'detail': 'Blocked visit check-in'}])
            raise UserError(self.env._('A fake GPS app was detected. Disable it to check in.'))

        partner = partner.sudo()
        offsite = bool(data.get('offsite'))
        vals = {
            'employee_id': employee.id,
            'partner_id': partner.id,
            'check_in_at': fields.Datetime.now(),
            'check_in_lat': lat,
            'check_in_lng': lng,
            'check_in_accuracy': _num(data.get('accuracy')) or 0.0,
            'check_in_mock': is_mock,
            'client_uuid': uuid,
        }
        if partner._ff_has_location():
            distance = haversine_m(lat, lng, partner.partner_latitude, partner.partner_longitude)
            radius = partner._ff_radius()
            inside = distance <= radius
            if not inside and settings['visit_block_outside']:
                raise UserError(self.env._(
                    'You are %(distance)s m away from %(client)s. Move within %(radius)s m to check in.',
                    distance=int(distance), client=partner.name, radius=radius))
            if not inside and not offsite:
                # The app asks "offsite visit?" and sends the check-in again with offsite=True.
                raise OffsiteConfirmation(int(distance), radius, partner.name)
            vals.update(distance_m=int(distance), inside_geofence=inside,
                        visit_type='onsite' if inside else 'offsite',
                        offsite_reason=False if inside else (data.get('offsite_reason') or False))
        else:
            # First visit of a client without coordinates: learn its location.
            partner.write({'partner_latitude': lat, 'partner_longitude': lng,
                           'date_localization': fields.Date.context_today(self)})
            vals.update(distance_m=0, inside_geofence=True, location_captured=True)

        visit = Visit.create(vals)
        partner.write({'ff_last_visit_at': visit.check_in_at, 'ff_last_visit_employee_id': employee.id})
        self.env['ff.location.ping'].ff_ingest(employee, [{
            'lat': lat, 'lng': lng, 'accuracy': vals['check_in_accuracy'], 'mock': is_mock, 'source': 'visit',
        }])
        return visit

    def ff_check_out(self, data):
        self.ensure_one()
        visit = self.sudo()
        if visit.state == 'done':
            return visit
        lat, lng = _num(data.get('lat')), _num(data.get('lng'))
        note = (data.get('note') or '').strip() or False
        photos = [p for p in (data.get('photos') or []) if isinstance(p, str) and p][:MAX_PHOTOS]
        outcome = self._ff_resolve_outcome(visit, data)
        if outcome.requires_note and not note:
            raise UserError(self.env._('Add a note for "%s".', outcome.name))
        if outcome.requires_photo and not photos and not visit.photo_count:
            raise UserError(self.env._('Add a photo for "%s".', outcome.name))
        code = outcome.code if outcome else data.get('outcome')
        visit.write({
            'state': 'done',
            'check_out_at': fields.Datetime.now(),
            'check_out_lat': lat or 0.0,
            'check_out_lng': lng or 0.0,
            'outcome_id': outcome.id or False,
            'outcome': code if code in dict(OUTCOMES) else 'other',
            'note': note,
        })
        if photos:
            self.env['ir.attachment'].sudo().create([{
                'name': 'visit_%s_%s.jpg' % (visit.id, index + 1),
                'datas': _strip_data_url(photo),
                'res_model': self._name,
                'res_id': visit.id,
                'mimetype': 'image/jpeg',
            } for index, photo in enumerate(photos)])
        if lat is not None and lng is not None:
            self.env['ff.location.ping'].ff_ingest(visit.employee_id, [{'lat': lat, 'lng': lng, 'source': 'visit'}])
        return visit

    def _ff_resolve_outcome(self, visit, data):
        """Outcome chosen in the app: by id, or by legacy code. Empty if none."""
        allowed = self.env['ff.visit.outcome'].ff_for(visit.employee_id, visit.partner_id)
        outcome_id = data.get('outcome_id')
        if outcome_id:
            outcome = allowed.filtered(lambda o: str(o.id) == str(outcome_id))
            if not outcome:
                raise UserError(self.env._('This outcome is not available for this visit.'))
            return outcome
        code = data.get('outcome')
        return allowed.filtered(lambda o: code and o.code == code)[:1]

    @api.model
    def _cron_auto_close(self):
        limit = fields.Datetime.now() - timedelta(hours=AUTO_CLOSE_HOURS)
        stale = self.sudo().search([('state', '=', 'ongoing'), ('check_in_at', '<', limit)])
        for visit in stale:
            visit.write({'state': 'done', 'check_out_at': visit.check_in_at + timedelta(hours=1),
                         'outcome': visit.outcome or 'other',
                         'note': (visit.note or '') + '\nAuto-closed: no check-out.'})
