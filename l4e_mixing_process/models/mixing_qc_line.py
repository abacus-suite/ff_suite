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
        default=1,
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
        default='pass',
        help="Select Pass or Fail for this quality check.",
    )
    remarks = fields.Char(
        string='Remarks',
        help="Optional remarks or sensory observations.",
    )

    @api.model_create_multi
    def create(self, vals_list):
        for vals in vals_list:
            process_id = vals.get('process_first_id') or vals.get('process_second_id')
            if not vals.get('sl_no') and process_id:
                domain = [('process_first_id', '=', vals.get('process_first_id'))] if vals.get('process_first_id') else [('process_second_id', '=', vals.get('process_second_id'))]
                last_line = self.search(domain, order='sl_no desc', limit=1)
                vals['sl_no'] = (last_line.sl_no + 1) if last_line else 1
        return super().create(vals_list)
