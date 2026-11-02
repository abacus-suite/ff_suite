# -*- coding: utf-8 -*-
from odoo import models, fields, api


class BrewingTeaQcLine(models.Model):
    _name = 'brewing.tea.qc.line'
    _description = 'Brewing Tea Quality Check Line'
    _order = 'brewing_id desc, sl_no asc, id asc'

    brewing_id = fields.Many2one(
        'brewing.tea',
        string='SI No',
        required=True,
        ondelete='cascade',
        index=True,
    )
    sl_no = fields.Integer(
        string='SI No',
        default=1,
        help="Serial number of the quality check step.",
    )
    description = fields.Char(
        string='Description',
        required=True,
        help="Parameter or test description.",
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
