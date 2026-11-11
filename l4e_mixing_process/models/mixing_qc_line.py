# -*- coding: utf-8 -*-
from odoo import models, fields, api


class MixingQcLine(models.Model):
    _name = 'mixing.qc.line'
    _description = 'Mixing Quality Check Line'
    _order = 'sl_no asc, id asc'

    process_first_id = fields.Many2one(
        'mixing.process',
        string='Mixing Process (1st QC)',
        ondelete='cascade',
        index=True,
    )
    process_second_id = fields.Many2one(
        'mixing.process',
        string='Mixing Process (2nd QC)',
        ondelete='cascade',
        index=True,
    )
    sl_no = fields.Integer(
        string='S.No',
        compute='_compute_sl_no',
        store=True,
        readonly=False,
        help="Serial number of the quality check entry.",
    )
    date = fields.Date(
        string='Date',
        default=fields.Date.context_today,
        required=True,
        help="Date when the QC check was performed.",
    )
    ph_value = fields.Float(
        string='PH Value',
        digits=(4, 2),
        required=True,
        help="Measured pH value for this quality check.",
    )
    status = fields.Selection(
        [
            ('pass', 'Pass'),
            ('fail', 'Fail'),
        ],
        string='Status',
        required=True,
        help="Select Pass or Fail manually for this quality check.",
    )
    remarks = fields.Char(
        string='Remarks',
        help="Optional remarks or sensory observations.",
    )

    @api.depends('process_first_id.first_qc_line_ids', 'process_second_id.second_qc_line_ids')
    def _compute_sl_no(self):
        for line in self:
            if line.process_first_id and line.process_first_id.first_qc_line_ids:
                lines = list(line.process_first_id.first_qc_line_ids)
                if line in lines:
                    line.sl_no = lines.index(line) + 1
                else:
                    line.sl_no = len(lines) + 1
            elif line.process_second_id and line.process_second_id.second_qc_line_ids:
                lines = list(line.process_second_id.second_qc_line_ids)
                if line in lines:
                    line.sl_no = lines.index(line) + 1
                else:
                    line.sl_no = len(lines) + 1
            else:
                line.sl_no = line.sl_no or 1

    @api.model_create_multi
    def create(self, vals_list):
        for vals in vals_list:
            process_id = vals.get('process_first_id') or vals.get('process_second_id')
            if not vals.get('sl_no') and process_id:
                domain = [('process_first_id', '=', vals.get('process_first_id'))] if vals.get('process_first_id') else [('process_second_id', '=', vals.get('process_second_id'))]
                last_line = self.search(domain, order='sl_no desc', limit=1)
                vals['sl_no'] = (last_line.sl_no + 1) if last_line else 1
        return super().create(vals_list)
