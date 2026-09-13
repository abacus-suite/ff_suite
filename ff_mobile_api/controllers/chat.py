"""Chat in the app through Odoo Discuss: the same channels and direct chats people use in Odoo.

A message sent from the phone is posted as the employee's Odoo user, so it shows
up in Discuss for everyone else - and replies from Odoo show up in the app.
"""
import re
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
        'last_message': _text(last.body)[:120] if last else None,
        'last_author': last.author_id.name if last else None,
        'last_at': to_iso(last.date) if last else None,
        'unread': unread,
    }


def _message_data(message, user):
    return {
        'id': message.id,
        'author': message.author_id.name or 'Odoo',
        'author_id': message.author_id.id,
        'mine': message.author_id == user.partner_id,
        'body': _text(message.body),
        'at': to_iso(message.date),
        'attachments': [{'id': a.id, 'name': a.name} for a in message.attachment_ids],
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
        channel = request.env['discuss.channel'].with_user(user).sudo(False)._get_or_create_chat(
            target.user_id.partner_id.ids)
        return ok(_channel_data(channel.sudo(), user))

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
        text = (body().get('body') or '').strip()
        if not text:
            raise ApiError('Write a message first.')
        html = Markup('<br/>').join(Markup(escape(line)) for line in text[:4000].split('\n'))
        message = channel.with_user(user).sudo(False).message_post(
            body=html, message_type='comment', subtype_xmlid='mail.mt_comment')
        return ok(_message_data(message.sudo(), user), status=201)

    @api_route('/api/v1/chat/channels/<int:channel_id>/seen', methods=('POST',))
    def seen(self, employee, channel_id, **kw):
        user = _user(employee)
        channel = _channel(user, channel_id)
        last = channel.message_ids[:1]
        member = _member(channel, user)
        if member and last:
            member.sudo().write({'seen_message_id': last.id})
        return ok({'seen': True})
