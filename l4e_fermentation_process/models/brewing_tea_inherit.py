# -*- coding: utf-8 -*-
from odoo import models, fields, api, _


class BrewingTea(models.Model):
    _inherit = 'brewing.tea'

    fermentation_ids = fields.One2many(
        'fermentation.process',
        'brewing_id',
        string='Fermentation Batches',
    )
    fermentation_count = fields.Integer(
        string='Fermentations',
        compute='_compute_fermentation_count',
    )

    @api.depends('fermentation_ids')
    def _compute_fermentation_count(self):
        for rec in self:
            rec.fermentation_count = len(rec.fermentation_ids)

    def action_view_fermentations(self):
        self.ensure_one()
        return {
            'name': _('Fermentation Batches for %s', self.name),
            'type': 'ir.actions.act_window',
            'res_model': 'fermentation.process',
            'view_mode': 'list,form',
            'domain': [('brewing_id', '=', self.id)],
            'context': {
                'default_brewing_id': self.id,
                'default_preparation_date': self.preparation_date,
                'default_quantity': self.quantity,
            },
        }

    def action_transfer_to_fermentation(self):
        self.ensure_one()
        return {
            'name': _('Transfer to Fermentation Tank'),
            'type': 'ir.actions.act_window',
            'res_model': 'fermentation.transfer.wizard',
            'view_mode': 'form',
            'target': 'new',
            'context': {
                'default_brewing_id': self.id,
                'default_preparation_date': self.preparation_date,
                'default_quantity': self.quantity,
            },
        }
