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

    @api.model
    def _register_hook(self):
        super()._register_hook()
        # Enforce dd/mm/yyyy date format across all active languages
        self.env.cr.execute("UPDATE res_lang SET date_format = '%%d/%%m/%%Y' WHERE active = TRUE;")
        # Self-healing: ensure all custom columns and tables exist in DB immediately
        # even if server boots before formal module upgrade
        cr = self.env.cr
        cols = [
            ("contact_person", "VARCHAR"),
            ("client_prospect", "VARCHAR"),
            ("client_status", "VARCHAR"),
            ("delivery_day", "VARCHAR"),
            ("scheme", "VARCHAR"),
            ("margin_percentage", "DOUBLE PRECISION"),
            ("credit_days", "VARCHAR"),
            ("outlet_onboard_date", "DATE"),
            ("chiller_availability", "VARCHAR"),
            ("chiller_model", "VARCHAR"),
            ("chiller_sr_no", "VARCHAR"),
            ("is_distributor", "BOOLEAN"),
            ("total_margin_pct", "DOUBLE PRECISION"),
            ("distributor_margin_pct", "DOUBLE PRECISION"),
            ("outlet_margin_pct", "DOUBLE PRECISION"),
            ("business_category_id", "INTEGER"),
            ("visible_to_id", "INTEGER"),
            ("marketing_material_id", "INTEGER"),
        ]
        for col_name, col_type in cols:
            cr.execute(f"ALTER TABLE res_partner ADD COLUMN IF NOT EXISTS {col_name} {col_type};")

        cr.execute("""
            CREATE TABLE IF NOT EXISTS business_category (
                id SERIAL PRIMARY KEY,
                name VARCHAR,
                active BOOLEAN DEFAULT TRUE,
                create_uid INTEGER,
                create_date TIMESTAMP,
                write_uid INTEGER,
                write_date TIMESTAMP
            );
            CREATE TABLE IF NOT EXISTS marketing_material (
                id SERIAL PRIMARY KEY,
                name VARCHAR,
                active BOOLEAN DEFAULT TRUE,
                create_uid INTEGER,
                create_date TIMESTAMP,
                write_uid INTEGER,
                write_date TIMESTAMP
            );
            CREATE TABLE IF NOT EXISTS distributor_mrp_line (
                id SERIAL PRIMARY KEY,
                partner_id INTEGER,
                product_id INTEGER,
                mrp DOUBLE PRECISION,
                create_uid INTEGER,
                create_date TIMESTAMP,
                write_uid INTEGER,
                write_date TIMESTAMP
            );
        """)
