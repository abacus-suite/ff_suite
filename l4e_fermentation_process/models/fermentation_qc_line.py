# -*- coding: utf-8 -*-
from odoo import models, fields, api


class FermentationQcLine(models.Model):
    _name = 'fermentation.qc.line'
    _description = 'Fermentation Quality Check Line'
    _order = 'process_id desc, sl_no asc, id asc'

    process_id = fields.Many2one(
        'fermentation.process',
        string='Fermentation Process',
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
        help="Quality check parameter (e.g. pH, Brix / Sugar, Acidity, Taste, Alcohol %).",
    )
    status = fields.Selection(
        [
            ('pass', 'Pass'),
            ('fail', 'Fail'),
        ],
        string='Pass / Fail',
        required=True,
        default='pass',
        help="Select Pass or Fail for this quality check parameter.",
    )
    remarks = fields.Char(
        string='Remarks / Measured Value',
        help="Optional measured value or observations (e.g. pH: 3.1, Brix: 5%).",
    )
    preparation_date = fields.Date(
        related='process_id.preparation_date',
        string='Preparation Date',
        store=True,
    )
    quantity = fields.Float(
        related='process_id.quantity',
        string='Quantity',
        store=True,
    )

    @api.depends('process_id.qc_line_ids')
    def _compute_sl_no(self):
        for line in self:
            parent = line.process_id
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
            if not vals.get('sl_no') and vals.get('process_id'):
                last_line = self.search(
                    [('process_id', '=', vals['process_id'])],
                    order='sl_no desc',
                    limit=1,
                )
                vals['sl_no'] = (last_line.sl_no + 1) if last_line else 1
        return super().create(vals_list)
