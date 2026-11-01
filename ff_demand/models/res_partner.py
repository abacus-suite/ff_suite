from odoo import api, fields, models


class ResPartner(models.Model):
    _inherit = 'res.partner'

    ff_is_distributor = fields.Boolean(string='Distributor', index=True,
                                       help='Supplies the outlets; the office quotes this partner, not the outlet.')
    ff_distributor_id = fields.Many2one('res.partner', string='Supplied by',
                                        domain=[('ff_is_distributor', '=', True)],
                                        help='Distributor who serves this outlet. Used to group demand.')

    def _auto_init(self):
        res = super()._auto_init()
        # Automatically populate distributor's primary or secondary territories and cities from mapped outlets
        self.env.cr.execute("""
            DO $$
            BEGIN
                IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'ff_partner_secondary_district_rel') THEN
                    -- Fill distributor's primary ff_district_id if null
                    UPDATE res_partner d
                    SET ff_district_id = o.ff_district_id
                    FROM res_partner o
                    WHERE o.ff_distributor_id = d.id
                    AND d.ff_district_id IS NULL
                    AND o.ff_district_id IS NOT NULL;

                    -- Insert secondary districts from mapped outlets
                    INSERT INTO ff_partner_secondary_district_rel (partner_id, district_id)
                    SELECT DISTINCT o.ff_distributor_id, o.ff_district_id
                    FROM res_partner o
                    JOIN res_partner d ON o.ff_distributor_id = d.id
                    WHERE o.ff_district_id IS NOT NULL
                    AND (d.ff_district_id IS NULL OR o.ff_district_id != d.ff_district_id)
                    AND NOT EXISTS (
                        SELECT 1 FROM ff_partner_secondary_district_rel r
                        WHERE r.partner_id = o.ff_distributor_id AND r.district_id = o.ff_district_id
                    );
                END IF;

                IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'ff_partner_secondary_territory_rel') THEN
                    -- Fill distributor's primary ff_territory_id if null
                    UPDATE res_partner d
                    SET ff_territory_id = o.ff_territory_id
                    FROM res_partner o
                    WHERE o.ff_distributor_id = d.id
                    AND d.ff_territory_id IS NULL
                    AND o.ff_territory_id IS NOT NULL;

                    -- Insert secondary territories from mapped outlets
                    INSERT INTO ff_partner_secondary_territory_rel (partner_id, territory_id)
                    SELECT DISTINCT o.ff_distributor_id, o.ff_territory_id
                    FROM res_partner o
                    JOIN res_partner d ON o.ff_distributor_id = d.id
                    WHERE o.ff_territory_id IS NOT NULL
                    AND (d.ff_territory_id IS NULL OR o.ff_territory_id != d.ff_territory_id)
                    AND NOT EXISTS (
                        SELECT 1 FROM ff_partner_secondary_territory_rel r
                        WHERE r.partner_id = o.ff_distributor_id AND r.territory_id = o.ff_territory_id
                    );
                END IF;
            END $$;
        """)
        return res

    @api.onchange('ff_distributor_id')
    def _onchange_ff_distributor_id(self):
        if self.ff_distributor_id:
            self._ff_sync_outlet_territory_and_city_to_distributor(self.ff_distributor_id)

    def _ff_sync_outlet_territory_and_city_to_distributor(self, distributor=None):
        """When an outlet selects a distributor, automatically propagate the outlet's
        territory and city to that distributor (primary if unset, else secondary)."""
        for outlet in self:
            dist = distributor or outlet.ff_distributor_id
            if not dist:
                continue

            # Collect all territories of the outlet (direct + secondary + beats)
            territories = outlet.env['ff.territory']
            if 'ff_territory_id' in outlet._fields and outlet.ff_territory_id:
                territories |= outlet.ff_territory_id
            if 'ff_secondary_territory_ids' in outlet._fields and outlet.ff_secondary_territory_ids:
                territories |= outlet.ff_secondary_territory_ids
            if 'ff_beat_line_ids' in outlet._fields and outlet.ff_beat_line_ids:
                territories |= outlet.ff_beat_line_ids.beat_id.territory_id

            # Collect all districts / cities of the outlet (direct + secondary + beats + from territories)
            districts = outlet.env['ff.district']
            if 'ff_district_id' in outlet._fields and outlet.ff_district_id:
                districts |= outlet.ff_district_id
            if 'ff_secondary_district_ids' in outlet._fields and outlet.ff_secondary_district_ids:
                districts |= outlet.ff_secondary_district_ids
            if 'ff_beat_line_ids' in outlet._fields and outlet.ff_beat_line_ids:
                districts |= outlet.ff_beat_line_ids.beat_id.district_id
            if territories:
                districts |= territories.mapped('district_id').filtered(bool)

            vals_to_write = {}
            # Sync territories
            if territories:
                if not dist.ff_territory_id:
                    vals_to_write['ff_territory_id'] = territories[0].id
                    extra_terr = territories[1:]
                else:
                    extra_terr = territories - dist.ff_territory_id

                if extra_terr and 'ff_secondary_territory_ids' in dist._fields:
                    missing_terr = extra_terr - dist.ff_secondary_territory_ids
                    if missing_terr:
                        vals_to_write['ff_secondary_territory_ids'] = [(4, t.id) for t in missing_terr]

            # Sync cities / districts
            if districts:
                if not dist.ff_district_id:
                    vals_to_write['ff_district_id'] = districts[0].id
                    extra_dist = districts[1:]
                else:
                    extra_dist = districts - dist.ff_district_id

                if extra_dist and 'ff_secondary_district_ids' in dist._fields:
                    missing_dist = extra_dist - dist.ff_secondary_district_ids
                    if missing_dist:
                        vals_to_write['ff_secondary_district_ids'] = [(4, d.id) for d in missing_dist]

            if vals_to_write:
                dist.sudo().write(vals_to_write)

    @api.model_create_multi
    def create(self, vals_list):
        partners = super().create(vals_list)
        for partner in partners:
            if partner.ff_distributor_id:
                partner._ff_sync_outlet_territory_and_city_to_distributor()
        return partners

    def write(self, vals):
        res = super().write(vals)
        if any(f in vals for f in ('ff_distributor_id', 'ff_territory_id', 'ff_secondary_territory_ids',
                                   'ff_district_id', 'ff_secondary_district_ids', 'ff_beat_line_ids')):
            for partner in self:
                if partner.ff_distributor_id:
                    partner._ff_sync_outlet_territory_and_city_to_distributor()
        return res
