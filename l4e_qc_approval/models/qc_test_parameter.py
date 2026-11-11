# -*- coding: utf-8 -*-
from odoo import models, fields, api, _
from odoo.exceptions import ValidationError


class QcTestParameter(models.Model):
    _name = 'qc.test.parameter'
    _description = 'QC Test / Approval Parameter'
    _inherit = ['mail.thread', 'mail.activity.mixin']
    _order = 'sequence asc, name asc, id asc'

    name = fields.Char(
        string='Test Name',
        required=True,
        tracking=True,
        help="Name of the quality parameter or test (e.g. pH Level, Sugar / Brix, Temperature, Sensory Taste).",
    )
    sequence = fields.Integer(
        string='Sequence',
        default=10,
    )
    test_type = fields.Selection(
        [
            ('numeric', 'Numeric Range (Min / Max)'),
            ('qualitative', 'Sensory / Qualitative (Pass / Fail)'),
        ],
        string='Test Type',
        default='numeric',
        required=True,
        tracking=True,
        help="Numeric tests enforce Min and Max tolerance thresholds. Qualitative tests evaluate sensory standards.",
    )
    min_value = fields.Float(
        string='Minimum Value',
        digits=(6, 2),
        tracking=True,
        help="Minimum acceptable value for this test.",
    )
    max_value = fields.Float(
        string='Maximum Value',
        digits=(6, 2),
        tracking=True,
        help="Maximum acceptable value for this test.",
    )
    unit = fields.Char(
        string='Unit / Symbol',
        help="Measurement unit or symbol (e.g. pH, °Bx, °C, %).",
    )
    display_range = fields.Char(
        string='Standard Range',
        compute='_compute_display_range',
        store=True,
        help="Display representation of acceptable limits.",
    )
    applies_to = fields.Selection(
        [
            ('all', 'All Processes'),
            ('brewing', 'Brewing Tea'),
            ('fermentation', 'Fermentation'),
            ('mixing', 'Mixing Process'),
        ],
        string='Applies To',
        default='all',
        required=True,
        tracking=True,
        help="Which manufacturing process this quality check applies to.",
    )
    active = fields.Boolean(
        string='Active',
        default=True,
    )
    description = fields.Text(
        string='SOP / Testing Instructions',
        help="Standard operating procedure or guidelines for performing this test.",
    )

    @api.depends('test_type', 'min_value', 'max_value', 'unit')
    def _compute_display_range(self):
        for rec in self:
            if rec.test_type == 'numeric':
                unit_str = f" {rec.unit}" if rec.unit else ""
                rec.display_range = f"{rec.min_value:.2f} - {rec.max_value:.2f}{unit_str}"
            else:
                rec.display_range = _("Pass / Fail (Sensory)")

    @api.constrains('test_type', 'min_value', 'max_value')
    def _check_min_max(self):
        for rec in self:
            if rec.test_type == 'numeric' and rec.min_value > rec.max_value:
                raise ValidationError(
                    _("Invalid Range for '%s': Minimum value (%s) cannot exceed Maximum value (%s).",
                      rec.name, rec.min_value, rec.max_value)
                )
