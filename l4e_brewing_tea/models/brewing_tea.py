# -*- coding: utf-8 -*-
from odoo import models, fields, api, _


class BrewingTea(models.Model):
    _name = 'brewing.tea'
    _description = 'Brewing Tea Master'
    _inherit = ['mail.thread', 'mail.activity.mixin']
    _order = 'preparation_date desc, id desc'

    name = fields.Char(
        string='SI No / Reference',
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
            ('draft', 'Draft'),
            ('pending', 'Pending QC'),
            ('pass', 'Pass'),
            ('fail', 'Fail'),
        ],
        string='QC Status',
        default='draft',
        compute='_compute_qc_status',
        store=True,
        readonly=False,
        tracking=True,
        help="Quality check status. Automatically evaluated from quality check lines or set manually.",
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
    notes = fields.Text(
        string='Notes / Remarks',
        help='Additional instructions or brewing notes.',
    )
    qc_line_ids = fields.One2many(
        'brewing.tea.qc.line',
        'brewing_id',
        string='Quality Check Lines',
        copy=True,
    )
    qc_count_pass = fields.Integer(
        string='Passed Checks',
        compute='_compute_qc_counts',
    )
    qc_count_fail = fields.Integer(
        string='Failed Checks',
        compute='_compute_qc_counts',
    )
    qc_count_total = fields.Integer(
        string='Total Checks',
        compute='_compute_qc_counts',
    )

    @api.depends('qc_line_ids.status')
    def _compute_qc_status(self):
        for rec in self:
            if not rec.qc_line_ids:
                if not rec.qc_status:
                    rec.qc_status = 'draft'
                continue
            statuses = [line.status for line in rec.qc_line_ids if line.status]
            if any(st == 'fail' for st in statuses):
                rec.qc_status = 'fail'
            elif statuses and all(st == 'pass' for st in statuses):
                rec.qc_status = 'pass'
            elif any(st == 'pending' for st in statuses):
                rec.qc_status = 'pending'
            else:
                rec.qc_status = 'draft'

    @api.depends('qc_line_ids.status')
    def _compute_qc_counts(self):
        for rec in self:
            rec.qc_count_total = len(rec.qc_line_ids)
            rec.qc_count_pass = sum(1 for line in rec.qc_line_ids if line.status == 'pass')
            rec.qc_count_fail = sum(1 for line in rec.qc_line_ids if line.status == 'fail')

    @api.model_create_multi
    def create(self, vals_list):
        for vals in vals_list:
            if not vals.get('name') or vals.get('name') == _('New'):
                vals['name'] = self.env['ir.sequence'].next_by_code('brewing.tea') or _('New')
        return super().create(vals_list)

    def action_mark_pass(self):
        self.ensure_one()
        self.qc_status = 'pass'

    def action_mark_fail(self):
        self.ensure_one()
        self.qc_status = 'fail'

    def action_reset_draft(self):
        self.ensure_one()
        self.qc_status = 'draft'

    def action_load_default_qc_lines(self):
        """Pre-fills standard Quality Check checkpoints for brewing tea."""
        self.ensure_one()
        default_checks = [
            'Brewing Temperature Check',
            'Extraction Time & Clarity',
            'Taste & Flavor Profile',
            'Brix / Sugar Concentration',
            'pH & Acidity Level',
            'Packaging & Sealing Inspection',
        ]
        start_sl = len(self.qc_line_ids) + 1
        lines = []
        for i, check_desc in enumerate(default_checks, start=start_sl):
            lines.append((0, 0, {
                'sl_no': i,
                'description': check_desc,
                'status': 'pending',
            }))
        self.write({'qc_line_ids': lines})
