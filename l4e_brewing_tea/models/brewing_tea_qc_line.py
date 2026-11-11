# -*- coding: utf-8 -*-
from odoo import models, fields, api


class BrewingTeaQcLine(models.Model):
    _name = 'brewing.tea.qc.line'
    _description = 'Brewing Tea Quality Check Line'
    _order = 'brewing_id desc, sl_no asc, id asc'

    brewing_id = fields.Many2one(
        'brewing.tea',
        string='Brewing Batch',
        required=True,
        ondelete='cascade',
        index=True,
    )
    sl_no = fields.Integer(
        string='SI No',
        compute='_compute_sl_no',
        store=True,
        readonly=False,
        help="Serial number of the quality check step.",
    )
    description = fields.Char(
        string='Description',
        required=True,
        help="Parameter or test description.",
    )
    preparation_date = fields.Date(
        related='brewing_id.preparation_date',
        string='Preparation Date',
        store=True,
    )
    quantity = fields.Float(
        related='brewing_id.quantity',
        string='Quantity',
        store=True,
    )
    status = fields.Selection(
        [
            ('pass', 'Pass'),
            ('fail', 'Fail'),
        ],
        string='Pass / Fail',
        required=True,
        help="Select Pass or Fail for this quality check parameter.",
    )

    @api.depends('brewing_id.qc_line_ids')
    def _compute_sl_no(self):
        for line in self:
            parent = line.brewing_id
            if parent and parent.qc_line_ids:
                lines = list(parent.qc_line_ids)
                if line in lines:
                    line.sl_no = lines.index(line) + 1
                else:
                    line.sl_no = len(lines) + 1
            else:
                line.sl_no = line.sl_no or 1

    @api.model_create_multi
    def create(self, vals_list):
        for vals in vals_list:
            if not vals.get('sl_no') and vals.get('brewing_id'):
                last_line = self.search(
                    [('brewing_id', '=', vals['brewing_id'])],
                    order='sl_no desc',
                    limit=1,
                )
                vals['sl_no'] = (last_line.sl_no + 1) if last_line else 1
        return super().create(vals_list)
