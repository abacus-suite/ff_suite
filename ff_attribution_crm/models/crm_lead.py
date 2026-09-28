from odoo import api, models


class CrmLead(models.Model):
    _name = 'crm.lead'
    _inherit = ['crm.lead', 'ff.attribution.mixin']

    @api.onchange('partner_id')
    def _onchange_partner_ff_attribution(self):
        self._ff_attribution_from_partner()

    @api.model_create_multi
    def create(self, vals_list):
        leads = super().create(vals_list)
        leads.filtered('partner_id')._ff_attribution_from_partner()
        return leads
