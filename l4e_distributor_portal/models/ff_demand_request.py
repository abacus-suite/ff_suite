import secrets

from markupsafe import Markup, escape

from odoo import api, fields, models
from odoo.exceptions import UserError


class FfDemandRequest(models.Model):
    _inherit = 'ff.demand.request'

    distributor_portal_token = fields.Char(default=lambda self: secrets.token_urlsafe(32), copy=False, index=True)
    distributor_portal_link = fields.Char(compute='_compute_portal_link', store=True, copy=False)

    @api.depends('distributor_portal_token')
    def _compute_portal_link(self):
        base = (self.env['ir.config_parameter'].sudo().get_param('web.base.url') or '').rstrip('/')
        for request in self:
            real = request._origin.id or (isinstance(request.id, int) and request.id)
            request.distributor_portal_link = (
                '%s/distributor/request/%s?token=%s' % (base, real, request.distributor_portal_token)
                if real and request.distributor_portal_token else False)

    @api.model_create_multi
    def create(self, vals_list):
        for vals in vals_list:
            vals.setdefault('distributor_portal_token', secrets.token_urlsafe(32))
        requests = super().create(vals_list)
        # The link needs the record's id, which exists only now.
        requests._compute_portal_link()
        return requests

    def _ff_sent(self):
        result = super()._ff_sent()
        if not self.env.context.get('ff_no_mail'):
            self.action_send_portal_mail(auto_sent=True)
        return result

    def action_send_portal_mail(self, auto_sent=False):
        """E-mail the distributor the link to approve this request and record deliveries."""
        for request in self:
            request.sudo()._compute_portal_link()
            recipient = request.partner_id
            if not recipient.email:
                message = self.env._("Could not e-mail the link: %s has no e-mail address.", recipient.name)
                request.message_post(body=message, subtype_xmlid='mail.mt_note')
                if not auto_sent:
                    raise UserError(message)
                continue
            link = request.distributor_portal_link
            body = (
                '<p>Dear %(name)s,</p>'
                '<p>New demand <strong>%(ref)s</strong> from the outlets in your area is waiting for you. '
                'Review it, adjust what you can supply and approve it. Afterwards record what you '
                'delivered to each outlet - the outlets are billed only for that.</p>'
                '<p style="margin:20px 0;"><a href="%(link)s" style="background:#1d4ed8;color:#fff;padding:12px 24px;'
                'text-decoration:none;border-radius:8px;font-weight:bold;display:inline-block;">'
                'Open the request</a></p><p>Thank you,<br/><strong>%(company)s</strong></p>') % {
                'name': escape(recipient.name), 'ref': escape(request.name), 'link': escape(link),
                'company': escape(request.company_id.name)}
            self.env['mail.mail'].sudo().create({
                'subject': self.env._('Demand %s is waiting for your approval', request.name),
                'body_html': body, 'email_to': recipient.email,
            }).send()
            request.message_post(
                body=Markup('<b>Link e-mailed</b> to %s (%s)<br/><a href="%s">%s</a>') % (
                    recipient.name, recipient.email, link, link),
                subtype_xmlid='mail.mt_note')
        return True

    def action_open_portal(self):
        self.ensure_one()
        return {'type': 'ir.actions.act_url', 'url': self.distributor_portal_link, 'target': 'new'}
