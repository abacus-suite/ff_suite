from odoo import api, fields, models


class ResPartner(models.Model):
    _inherit = 'res.partner'

    # ── Contact / Business Information ─────────────────────────────────────────
    contact_person = fields.Char(
        string='Contact Person',
    )
    business_category_id = fields.Many2one(
        'business.category',
        string='Business Category',
    )
    client_prospect = fields.Selection(
        selection=[
            ('client', 'Client'),
            ('prospect', 'Prospect'),
        ],
        string='Client / Prospect',
    )
    client_status = fields.Selection(
        selection=[
            ('new_lead', 'New Lead'),
            ('confirmed', 'Confirmed'),
            ('onboarded', 'Onboarded'),
            ('stopped', 'Stopped'),
            ('not_interested', 'Not Interested'),
        ],
        string='Client Status',
    )
    visible_to_id = fields.Many2one(
        'hr.employee',
        string='Visible To',
        help='Assigned sales / field representative',
    )
    delivery_day = fields.Selection(
        selection=[
            ('monday', 'Monday'),
            ('tuesday', 'Tuesday'),
            ('wednesday', 'Wednesday'),
            ('thursday', 'Thursday'),
            ('friday', 'Friday'),
            ('saturday', 'Saturday'),
            ('sunday', 'Sunday'),
            ('other', 'Other'),
        ],
        string='Delivery Day',
    )
    scheme = fields.Char(
        string='Scheme',
    )
    margin_percentage = fields.Float(
        string='Margin %',
    )
    outlet_onboard_date = fields.Date(
        string='Outlet Onboarded Date',
    )
    marketing_material_id = fields.Many2one(
        'marketing.material',
        string='Marketing Materials',
    )

    # ── Chiller Details ───────────────────────────────────────────────────────
    chiller_availability = fields.Selection(
        selection=[
            ('yes', 'YES'),
            ('no', 'NO'),
        ],
        string='Chiller Availability',
    )
    chiller_model = fields.Char(
        string='Model',
    )
    chiller_sr_no = fields.Char(
        string='SR Number',
    )

    # ── Distributor Margin & MRP Details ──────────────────────────────────────
    is_distributor = fields.Boolean(
        string='Is Distributor',
        compute='_compute_is_distributor',
        store=True,
    )
    distributor_margin_pct = fields.Float(
        string='Distributor Margin %',
    )
    outlet_margin_pct = fields.Float(
        string='Outlet Margin %',
    )
    total_margin_pct = fields.Float(
        string='Total Margin %',
        compute='_compute_total_margin',
        store=True,
        readonly=False,
    )
    distributor_mrp_line_ids = fields.One2many(
        'distributor.mrp.line',
        'partner_id',
        string='MRP Lines',
    )

    @api.depends('distributor_margin_pct', 'outlet_margin_pct')
    def _compute_total_margin(self):
        for partner in self:
            partner.total_margin_pct = (partner.distributor_margin_pct or 0.0) + (partner.outlet_margin_pct or 0.0)

    @api.depends('ff_category_id', 'ff_category_id.name', 'ff_category_type')
    def _compute_is_distributor(self):
        for partner in self:
            is_dist = False
            if hasattr(partner, 'ff_category_type') and partner.ff_category_type == 'distributor':
                is_dist = True
            elif hasattr(partner, 'ff_category_id') and partner.ff_category_id and 'distributor' in (partner.ff_category_id.name or '').lower():
                is_dist = True
            partner.is_distributor = is_dist


