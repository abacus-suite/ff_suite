# -*- coding: utf-8 -*-
from odoo import models, fields, api, _


class FermentationTank(models.Model):
    _name = 'fermentation.tank'
    _description = 'Fermentation Tank'
    _order = 'name asc'

    name = fields.Char(string='Tank Name', required=True, index=True)
    code = fields.Char(string='Tank Code', index=True)
    capacity = fields.Float(string='Capacity (L)', help='Maximum capacity in Litres')
    state = fields.Selection(
        [
            ('available', 'Available'),
            ('occupied', 'Occupied'),
            ('maintenance', 'Maintenance'),
        ],
        string='Status',
        default='available',
        required=True,
        index=True,
    )
    active = fields.Boolean(default=True)
    current_process_id = fields.Many2one(
        'fermentation.process',
        string='Current Fermentation Batch',
        ondelete='set null',
    )
    brewing_id = fields.Many2one(
        'brewing.tea',
        related='current_process_id.brewing_id',
        string='Current Brewing Tea',
        readonly=True,
    )
    process_ids = fields.One2many(
        'fermentation.process',
        'tank_id',
        string='Fermentation History',
    )
    process_count = fields.Integer(
        string='Batch Count',
        compute='_compute_process_count',
    )

    @api.depends('process_ids')
    def _compute_process_count(self):
        for tank in self:
            tank.process_count = len(tank.process_ids)

    def action_view_processes(self):
        self.ensure_one()
        return {
            'name': _('Batches for %s', self.name),
            'type': 'ir.actions.act_window',
            'res_model': 'fermentation.process',
            'view_mode': 'list,form',
            'domain': [('tank_id', '=', self.id)],
            'context': {'default_tank_id': self.id},
        }
