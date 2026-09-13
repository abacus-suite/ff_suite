"""Chat in the app through Odoo Discuss: the same channels and direct chats people use in Odoo.

A message sent from the phone is posted as the employee's Odoo user, so it shows
up in Discuss for everyone else - and replies from Odoo show up in the app.
"""
import base64
import hashlib
import hmac
import re
import time as clock
from html import escape

from markupsafe import Markup

from odoo import http
from odoo.http import request

from odoo.addons.ff_base.tools import to_iso

from .clients import to_int
from .common import ApiError, api_route, body, ok


def _user(employee):
    user = employee.sudo().user_id
    if not user or not user.active:
        raise ApiError('Chat needs an Odoo user on your employee record. Ask the office to link one.', 403, 'no_user')
    return user


def _text(html):
    if not html:
        return ''
    text = re.sub(r'<br\s*/?>|</p>', '\n', str(html))
    text = re.sub(r'<[^>]+>', '', text)
    return (text.replace('&nbsp;', ' ').replace('&amp;', '&').replace('&lt;', '<')
            .replace('&gt;', '>').replace('&#39;', "'").replace('&quot;', '"')).strip()


def _channel(user, channel_id):
    channel = request.env['discuss.channel'].sudo().browse(channel_id).exists()
    if not channel or user.partner_id not in channel.channel_member_ids.partner_id:
        raise ApiError('Conversation not found.', 404, 'not_found')
    return channel


def _member(channel, user):
    return channel.channel_member_ids.filtered(lambda m: m.partner_id == user.partner_id)[:1]


def _channel_data(channel, user):
    member = _member(channel, user)
    last = channel.message_ids.filtered(lambda m: m.message_type in ('comment', 'email'))[:1]
    preview = None
    if last:
        preview = _text(last.body) or ('📎 %s' % last.attachment_ids[:1].name if last.attachment_ids else '')
    others = channel.channel_member_ids.partner_id - user.partner_id
    name = channel.name
    if channel.channel_type == 'chat':
        name = ', '.join(others.mapped('name')) or channel.name
    seen = member.seen_message_id.id if member and member.seen_message_id else 0
    unread = len(channel.message_ids.filtered(
        lambda m: m.id > seen and m.author_id != user.partner_id and m.message_type in ('comment', 'email')))
    return {
        'id': channel.id,
        'name': name,
        'type': channel.channel_type,
        'members': len(channel.channel_member_ids),
        'last_message': preview[:120] if preview else None,
        'last_author': last.author_id.name if last else None,
        'last_at': to_iso(last.date) if last else None,
        'unread': unread,
    }


MAX_ATTACHMENT_BYTES = 25 * 1024 * 1024
LINK_SECONDS = 3600


def _sign(attachment_id):
    secret = request.env['ir.config_parameter'].sudo().get_param('database.secret').encode()
    expires = int(clock.time()) + LINK_SECONDS
    digest = hmac.new(secret, ('%s.%s' % (attachment_id, expires)).encode(), hashlib.sha256).hexdigest()
    return '/api/v1/chat/file/%s?e=%s&s=%s' % (attachment_id, expires, digest)


def _attachment_data(attachment):
    return {'id': attachment.id, 'name': attachment.name, 'mimetype': attachment.mimetype or '',
            'size': attachment.file_size, 'url': _sign(attachment.id)}


def _message_data(message, user):
    return {
        'id': message.id,
        'author': message.author_id.name or 'Odoo',
        'author_id': message.author_id.id,
        'mine': message.author_id == user.partner_id,
        'body': _text(message.body),
        'at': to_iso(message.date),
        'attachments': [_attachment_data(a) for a in message.attachment_ids],
    }


class FieldForceChatApi(http.Controller):

    @api_route('/api/v1/chat/channels', methods=('GET',))
    def channels(self, employee, **kw):
        user = _user(employee)
        channels = request.env['discuss.channel'].sudo().search(
            [('channel_member_ids.partner_id', '=', user.partner_id.id)])
        rows = [_channel_data(channel, user) for channel in channels]
        rows.sort(key=lambda row: row['last_at'] or '', reverse=True)
        return ok({'channels': rows, 'unread': sum(row['unread'] for row in rows)})

    @api_route('/api/v1/chat/people', methods=('GET',))
    def people(self, employee, **kw):
        """Who this employee can start a chat with: their manager and the people in their Data Access."""
        user = _user(employee)
        candidates = (employee._ff_scope_employees() | employee.parent_id) - employee
        if employee.ff_team_id:
            candidates |= request.env['hr.employee'].sudo().search([('ff_team_id', '=', employee.ff_team_id.id)]) - employee
        rows = [{'employee_id': person.id, 'name': person.name, 'job': person.job_title or None,
                 'team': person.ff_team_id.name or None}
                for person in candidates.sudo().sorted('name') if person.user_id and person.user_id != user]
        return ok(rows)

    @api_route('/api/v1/chat/direct', methods=('POST',))
    def direct(self, employee, **kw):
        user = _user(employee)
        target = request.env['hr.employee'].sudo().browse(to_int(body().get('employee_id')) or []).exists()
        if not target or not target.user_id:
            raise ApiError('That person has no Odoo user to chat with.', 404, 'not_found')
        # The app talks to Odoo as the public user, so Discuss helpers that read the
        # "current user" from the request cannot be used: find or make the chat directly.
        pair = user.partner_id | target.user_id.partner_id
        Channel = request.env['discuss.channel'].sudo()
        channel = Channel.browse()
        for candidate in Channel.search([('channel_type', '=', 'chat'),
                                         ('channel_member_ids.partner_id', '=', user.partner_id.id)]):
            if candidate.channel_member_ids.partner_id == pair:
                channel = candidate
                break
        if not channel:
            channel = Channel.create({
                'name': ', '.join(pair.mapped('name')),
                'channel_type': 'chat',
                'channel_member_ids': [(0, 0, {'partner_id': partner.id}) for partner in pair],
            })
        return ok(_channel_data(channel, user))

    @api_route('/api/v1/chat/channels/<int:channel_id>/messages', methods=('GET',))
    def messages(self, employee, channel_id, before_id=None, after_id=None, limit=None, **kw):
        user = _user(employee)
        channel = _channel(user, channel_id)
        domain = [('model', '=', 'discuss.channel'), ('res_id', '=', channel.id),
                  ('message_type', 'in', ('comment', 'email'))]
        if before_id:
            domain.append(('id', '<', to_int(before_id)))
        if after_id:
            domain.append(('id', '>', to_int(after_id)))
        messages = request.env['mail.message'].sudo().search(domain, order='id desc', limit=min(to_int(limit) or 40, 100))
        return ok({'channel': _channel_data(channel, user),
                   'messages': [_message_data(m, user) for m in reversed(messages)]})

    @api_route('/api/v1/chat/channels/<int:channel_id>/messages', methods=('POST',))
    def post(self, employee, channel_id, **kw):
        user = _user(employee)
        channel = _channel(user, channel_id)
        data = body()
        text = (data.get('body') or '').strip()
        files = [f for f in (data.get('attachments') or []) if isinstance(f, dict) and f.get('data')][:10]
        if not text and not files:
            raise ApiError('Write a message or add a file.')
        attachments = request.env['ir.attachment'].sudo()
        for item in files:
            raw = item['data'].split(',', 1)[1] if ',' in item['data'][:100] else item['data']
            try:
                content = base64.b64decode(raw, validate=True)
            except ValueError:
                raise ApiError('A file could not be read.')
            if len(content) > MAX_ATTACHMENT_BYTES:
                raise ApiError('Files must be under 25 MB.')
            attachments |= attachments.create({
                'name': (item.get('name') or 'file')[:200], 'raw': content,
                'mimetype': item.get('mimetype') or 'application/octet-stream',
                'res_model': 'discuss.channel', 'res_id': channel.id,
            })
        html = Markup('<br/>').join(Markup(escape(line)) for line in text[:4000].split('\n')) if text else ''
        message = channel.sudo().with_context(mail_create_nosubscribe=True).message_post(
            body=html, author_id=user.partner_id.id, message_type='comment', subtype_xmlid='mail.mt_comment',
            attachment_ids=attachments.ids)
        return ok(_message_data(message.sudo(), user), status=201)

    @http.route('/api/v1/chat/file/<int:attachment_id>', type='http', auth='public', methods=['GET'],
                csrf=False, save_session=False)
    def file(self, attachment_id, e=None, s=None, **kw):
        """A chat file, opened by a signed link the app got from a message (images, video, documents)."""
        secret = request.env['ir.config_parameter'].sudo().get_param('database.secret').encode()
        expected = hmac.new(secret, ('%s.%s' % (attachment_id, e)).encode(), hashlib.sha256).hexdigest()
        if not s or not e or not hmac.compare_digest(expected, s) or int(e) < clock.time():
            return request.make_response('This link has expired.', status=410)
        attachment = request.env['ir.attachment'].sudo().browse(attachment_id).exists()
        if not attachment or attachment.res_model != 'discuss.channel':
            return request.not_found()
        name = (attachment.name or 'file').replace('"', '')
        disposition = 'inline' if (attachment.mimetype or '').startswith(('image/', 'video/')) else 'attachment'
        return request.make_response(attachment.raw or b'', headers=[
            ('Content-Type', attachment.mimetype or 'application/octet-stream'),
            ('Content-Disposition', '%s; filename="%s"' % (disposition, name)),
            ('Cache-Control', 'private, max-age=3600'),
        ])

    @api_route('/api/v1/chat/channels/<int:channel_id>/seen', methods=('POST',))
    def seen(self, employee, channel_id, **kw):
        user = _user(employee)
        channel = _channel(user, channel_id)
        last = channel.message_ids[:1]
        member = _member(channel, user)
        if member and last:
            member.sudo().write({'seen_message_id': last.id})
        return ok({'seen': True})
