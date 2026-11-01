from odoo import api, fields, models


class ResPartner(models.Model):
    _inherit = 'res.partner'

    ff_hub_user_id = fields.Many2one('res.users', string='Dealer Hub Login', readonly=True, copy=False,
                                     ondelete='set null')
    ff_hub_login = fields.Char(related='ff_hub_user_id.login', string='Hub Login')
    ff_hub_active = fields.Boolean(compute='_compute_hub_active', string='Hub Access On')

    @api.depends('ff_hub_user_id.active')
    def _compute_hub_active(self):
        for partner in self:
            partner.ff_hub_active = bool(partner.ff_hub_user_id and partner.ff_hub_user_id.active)

    def action_open_hub_access(self):
        self.ensure_one()
        return {
            'type': 'ir.actions.act_window', 'name': self.env._('Dealer Hub Login'),
            'res_model': 'l4e.dealer.hub.access', 'view_mode': 'form', 'target': 'new',
            'context': {'default_partner_id': self.id},
        }

    def action_open_hub_preview(self):
        """Open this distributor's Dealer Hub as the signed-in Odoo user: no login as the distributor."""
        self.ensure_one()
        return {'type': 'ir.actions.act_url', 'url': '/dealer?as=%s' % self.id, 'target': 'new'}

    def action_hub_disable(self):
        self.mapped('ff_hub_user_id').sudo().write({'active': False})
        return True
