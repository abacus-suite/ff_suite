# -*- coding: utf-8 -*-
from odoo import models, fields, api, _


class BrewingTea(models.Model):
    _name = 'brewing.tea'
    _description = 'Brewing Tea Master'
    _inherit = ['mail.thread', 'mail.activity.mixin']
    _order = 'preparation_date desc, id desc'

    name = fields.Char(
        string='SI No',
        required=True,
        copy=False,
        readonly=True,
        index=True,
        default=lambda self: _('New'),
        tracking=True,
    )
    preparation_date = fields.Date(
        string='Preparation Date',
        default=fields.Date.context_today,
        required=True,
        tracking=True,
        help="Date on which the tea brewing batch was prepared.",
    )
    quantity = fields.Float(
        string='Quantity',
        digits='Product Unit of Measure',
        default=0.0,
        required=True,
        tracking=True,
        help="Quantity produced or brewed for this batch.",
    )
    qc_status = fields.Selection(
        [
            ('pass', 'Pass'),
            ('fail', 'Fail'),
        ],
        string='QC Status',
        compute='_compute_qc_status',
        store=True,
        tracking=True,
        help="Overall quality check status, automatically determined by the Quality Check lines.",
    )
    user_id = fields.Many2one(
        'res.users',
        string='Responsible / Prepared By',
        default=lambda self: self.env.user,
        tracking=True,
    )
    company_id = fields.Many2one(
        'res.company',
        string='Company',
        default=lambda self: self.env.company,
        required=True,
    )
    qc_line_ids = fields.One2many(
        'brewing.tea.qc.line',
        'brewing_id',
        string='Quality Check Lines',
        copy=True,
    )

    @api.depends('qc_line_ids.status')
    def _compute_qc_status(self):
        for rec in self:
            if not rec.qc_line_ids:
                rec.qc_status = False
                continue
            statuses = [line.status for line in rec.qc_line_ids if line.status]
            if any(st == 'fail' for st in statuses):
                rec.qc_status = 'fail'
            elif statuses and all(st == 'pass' for st in statuses):
                rec.qc_status = 'pass'
            else:
                rec.qc_status = False

    @api.model_create_multi
    def create(self, vals_list):
        for vals in vals_list:
            if not vals.get('name') or vals.get('name') == _('New'):
                vals['name'] = self.env['ir.sequence'].next_by_code('brewing.tea') or _('New')
        return super().create(vals_list)
