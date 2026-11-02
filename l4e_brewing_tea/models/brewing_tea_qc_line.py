# -*- coding: utf-8 -*-
from odoo import models, fields, api


class BrewingTeaQcLine(models.Model):
    _name = 'brewing.tea.qc.line'
    _description = 'Brewing Tea Quality Check Line'
    _order = 'sl_no asc, id asc'

    brewing_id = fields.Many2one(
        'brewing.tea',
        string='Brewing Reference',
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
        help="Parameter or test description (e.g. Temperature, Color, Taste, pH).",
    )
    status = fields.Selection(
        [
            ('pending', 'Pending'),
            ('pass', 'Pass'),
            ('fail', 'Fail'),
        ],
        string='Pass / Fail',
        default='pending',
        required=True,
        help="Result of this quality check parameter.",
    )
    remarks = fields.Char(
        string='Remarks',
        help="Specific observations, values recorded, or rejection notes.",
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
