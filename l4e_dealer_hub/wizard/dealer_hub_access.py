from odoo import Command, fields, models
from odoo.exceptions import UserError


class DealerHubAccess(models.TransientModel):
    _name = 'l4e.dealer.hub.access'
    _description = 'Dealer Hub Login'

    partner_id = fields.Many2one('res.partner', required=True, ondelete='cascade')
    login = fields.Char(string='Login', required=True,
                        help='What the distributor types to sign in. Usually their e-mail address.')
    password = fields.Char(required=True)

    def default_get(self, fields_list):
        values = super().default_get(fields_list)
        partner = self.env['res.partner'].browse(values.get('partner_id'))
        if partner:
            values['login'] = partner.ff_hub_user_id.login or partner.email or False
        return values

    def action_apply(self):
        self.ensure_one()
        partner = self.partner_id.sudo()
        login = (self.login or '').strip()
        if len(self.password or '') < 6:
            raise UserError(self.env._('Use a password of at least 6 characters.'))
        Users = self.env['res.users'].sudo().with_context(no_reset_password=True)
        user = partner.ff_hub_user_id
        if not user:
            existing = Users.with_context(active_test=False).search([('partner_id', '=', partner.id)], limit=1)
            if existing and not existing.share:
                raise UserError(self.env._(
                    '%s is an internal user. Use a separate contact for the distributor.', partner.name))
            user = existing
        if user:
            user.write({'login': login, 'password': self.password, 'active': True})
        else:
            groups = 'group_ids' if 'group_ids' in Users._fields else 'groups_id'
            user = Users.create({
                'name': partner.name, 'login': login, 'password': self.password,
                'partner_id': partner.id, 'company_id': partner.company_id.id or self.env.company.id,
                groups: [Command.set([self.env.ref('base.group_portal').id])],
            })
        partner.ff_hub_user_id = user.id
        partner.message_post(body=self.env._('Dealer Hub login %s was set.', login))
        return {'type': 'ir.actions.act_window_close'}
