from odoo import api, fields, models
from odoo.exceptions import AccessError, UserError

MAX_PHOTOS = 5


def _strip_data_url(image):
    if isinstance(image, str) and image.startswith('data:') and ',' in image:
        return image.split(',', 1)[1]
    return image


class FfVisitStepRecord(models.Model):
    """What happened for one step of one visit."""
    _name = 'ff.visit.step.record'
    _description = 'Visit Step Result'
    _order = 'visit_id, sequence, id'

    visit_id = fields.Many2one('ff.visit', required=True, index=True, ondelete='cascade')
    step_id = fields.Many2one('ff.visit.step', required=True, index=True, ondelete='restrict')
    sequence = fields.Integer(related='step_id.sequence', store=True)
    step_type = fields.Selection(related='step_id.step_type', store=True)
    employee_id = fields.Many2one(related='visit_id.employee_id', store=True)
    partner_id = fields.Many2one(related='visit_id.partner_id', store=True)
    state = fields.Selection([('done', 'Done'), ('skipped', 'Skipped')], required=True, default='done')
    note = fields.Text()
    skip_reason = fields.Char()
    data = fields.Json()
    stock_count_id = fields.Many2one('ff.stock.count', ondelete='set null')
    done_at = fields.Datetime(required=True, default=fields.Datetime.now)

    _visit_step_uniq = models.Constraint('UNIQUE(visit_id, step_id)', 'This step is already recorded for the visit.')

    @api.depends('step_id', 'visit_id')
    def _compute_display_name(self):
        for record in self:
            record.display_name = '%s - %s' % (record.visit_id.display_name or '', record.step_id.name or '')

    @api.model
    def ff_complete(self, employee, visit, step, data):
        """Record a step from the app (done or skipped) and store its payload."""
        if visit.employee_id != employee:
            raise AccessError(self.env._('This visit is not yours.'))
        if step not in self.env['ff.visit.step'].ff_for(employee, visit.partner_id):
            raise AccessError(self.env._('This step does not apply to this visit.'))

        skipped = bool(data.get('skip'))
        skip_reason = (data.get('skip_reason') or '').strip()
        note = (data.get('note') or '').strip()
        if skipped:
            if not step.allow_skip:
                raise UserError(self.env._('"%s" cannot be skipped.', step.name))
            if step.skip_reason_required and not skip_reason:
                raise UserError(self.env._('Give a reason for skipping "%s".', step.name))
        elif step.step_type == 'note' and not note:
            raise UserError(self.env._('Write the visit notes for "%s".', step.name))

        photos = [p for p in (data.get('photos') or []) if isinstance(p, str) and p][:MAX_PHOTOS]
        if not skipped and step.step_type == 'photo' and not photos:
            raise UserError(self.env._('Add a photo for "%s".', step.name))

        stock_count = self.env['ff.stock.count']
        payload = {}
        if not skipped and step.step_type == 'stock':
            lines = data.get('lines') or []
            if not lines:
                raise UserError(self.env._('Count at least one product for "%s".', step.name))
            stock_count = stock_count.ff_record(employee, visit.partner_id, lines, visit=visit, note=note)
            payload = {'stock_count_id': stock_count.id, 'items': len(stock_count.line_ids)}

        Record = self.sudo()
        record = Record.search([('visit_id', '=', visit.id), ('step_id', '=', step.id)], limit=1)
        vals = {
            'state': 'skipped' if skipped else 'done',
            'note': note or False,
            'skip_reason': skip_reason or False,
            'data': payload or None,
            'stock_count_id': stock_count.id or False,
            'done_at': fields.Datetime.now(),
        }
        if record:
            record.write(vals)
        else:
            record = Record.create(dict(vals, visit_id=visit.id, step_id=step.id))
        if photos:
            self.env['ir.attachment'].sudo().create([{
                'name': 'step_%s_%s.jpg' % (record.id, index + 1),
                'datas': _strip_data_url(photo),
                'res_model': self._name,
                'res_id': record.id,
                'mimetype': 'image/jpeg',
            } for index, photo in enumerate(photos)])
        return record
