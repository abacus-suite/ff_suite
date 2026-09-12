"""One employee's day, told in order: punches, travel, halts and what happened.

The panel draws this as a list on the left and a route on the right, so the
payload is one ordered list of events plus the path they were recorded along.
"""
from odoo import api, fields, models

from odoo.addons.ff_base.tools import haversine_m, path_distance_km, to_iso

MAX_POINTS = 1200


class FfDashboardTimeline(models.AbstractModel):
    _inherit = 'ff.dashboard'

    @api.model
    def ff_employee_timeline(self, employee_id, day=None):
        employee = self.env['hr.employee'].sudo().browse(int(employee_id or 0)).exists()
        if not employee or employee not in self._ff_employees():
            return {'events': [], 'path': [], 'summary': {}}
        day = fields.Date.to_date(day) if day else self._ff_today()
        start, end = self._ff_day_range(day)

        pings = self.env['ff.location.ping'].sudo().search(
            [('employee_id', '=', employee.id), ('ts', '>=', start), ('ts', '<', end)], order='ts asc')
        attendances = self.env['hr.attendance'].sudo().search(
            [('employee_id', '=', employee.id), ('check_in', '>=', start), ('check_in', '<', end)],
            order='check_in asc')
        visits = self.env['ff.visit'].sudo().search(
            [('employee_id', '=', employee.id), ('check_in_at', '>=', start), ('check_in_at', '<', end)],
            order='check_in_at asc')

        events = []
        events += self._punch_events(attendances)
        events += self._visit_events(visits)
        events += self._order_events(employee, start, end)
        events += self._form_events(employee, start, end)
        events += self._expense_events(employee, start, end)
        events += self._collection_events(employee, start, end)
        events.sort(key=lambda event: event['at'] or '')
        events = self._with_travel(events, pings)

        return {
            'employee': {'id': employee.id, 'name': employee.name,
                         'code': employee.ff_employee_code or '',
                         'avatar': '/web/image/hr.employee/%s/avatar_128' % employee.id},
            'date': day.isoformat(),
            'summary': self._summary(employee, day, pings, attendances, visits),
            'path': self._path(pings),
            'events': events,
        }

    # ------------------------------------------------------------------
    @api.model
    def ff_timeline_employees(self):
        """Who can be chosen in the timeline picker."""
        return [{'id': employee.id, 'name': employee.name, 'code': employee.ff_employee_code or ''}
                for employee in self._ff_employees().sorted('name')]

    def _summary(self, employee, day, pings, attendances, visits):
        track = self.env['ff.daily.track'].sudo().search(
            [('employee_id', '=', employee.id), ('date', '=', day)], limit=1)
        distance = track.distance_km if track else path_distance_km(
            [(ping.ts, ping.latitude, ping.longitude, ping.accuracy) for ping in pings])
        first_in = attendances[:1].check_in if attendances else False
        last_out = attendances[-1:].check_out if attendances else False
        tracked_minutes = 0
        if pings:
            tracked_minutes = int((pings[-1].ts - pings[0].ts).total_seconds() // 60)
        return {
            'punch_in': to_iso(first_in),
            'punch_out': to_iso(last_out),
            'hours': round(sum(attendances.mapped('worked_hours') or [0.0]), 2),
            'tracked_minutes': tracked_minutes,
            'distance_km': round(distance or 0.0, 2),
            'visits': len(visits),
            'productive': len(visits.filtered('productive')),
            'pings': len(pings),
        }

    def _path(self, pings):
        """The travelled line, thinned so the browser can draw it."""
        if not pings:
            return []
        step = len(pings) // MAX_POINTS + 1
        sampled = pings[::step]
        if sampled and sampled[-1] != pings[-1]:
            sampled |= pings[-1]
        return [{'lat': ping.latitude, 'lng': ping.longitude, 'at': to_iso(ping.ts)}
                for ping in sampled if ping.latitude or ping.longitude]

    # -- the events ----------------------------------------------------
    def _punch_events(self, attendances):
        """Punches carry the selfie and the address the app captured."""
        events = []
        for attendance in attendances:
            fields_present = attendance._fields
            events.append({
                'kind': 'punch_in', 'title': 'Punch In', 'at': to_iso(attendance.check_in),
                'note': attendance.ff_in_address or '',
                'source': attendance.ff_source,
                'lat': attendance.in_latitude if 'in_latitude' in fields_present else 0.0,
                'lng': attendance.in_longitude if 'in_longitude' in fields_present else 0.0,
                'photos': (['/web/image/hr.attendance/%s/ff_in_selfie' % attendance.id]
                           if attendance.ff_in_selfie else []),
                'res_id': attendance.id,
            })
            if attendance.check_out:
                events.append({
                    'kind': 'punch_out', 'title': 'Punch Out', 'at': to_iso(attendance.check_out),
                    'note': attendance.ff_out_address or '',
                    'source': attendance.ff_source,
                    'lat': attendance.out_latitude if 'out_latitude' in fields_present else 0.0,
                    'lng': attendance.out_longitude if 'out_longitude' in fields_present else 0.0,
                    'photos': (['/web/image/hr.attendance/%s/ff_out_selfie' % attendance.id]
                               if attendance.ff_out_selfie else []),
                    'res_id': attendance.id,
                })
        return events

    def _visit_events(self, visits):
        events = []
        for visit in visits:
            events.append({
                'kind': 'visit',
                'title': visit.partner_id.display_name,
                'at': to_iso(visit.check_in_at),
                'until': to_iso(visit.check_out_at),
                'duration_min': visit.duration_min,
                'state': visit.state,
                'outcome': visit.outcome_id.name or visit.outcome or '',
                'inside_geofence': visit.inside_geofence,
                'note': visit.note or '',
                'lat': visit.check_in_lat,
                'lng': visit.check_in_lng,
                'photos': self._photos('ff.visit', visit.id),
                'res_id': visit.id,
            })
        return events

    def _order_events(self, employee, start, end):
        if 'sale.order' not in self.env:
            return []
        orders = self.env['sale.order'].sudo().search([
            ('ff_employee_id', '=', employee.id), ('date_order', '>=', start), ('date_order', '<', end)])
        return [{
            'kind': 'order', 'title': '%s - %s' % (order.name, order.partner_id.display_name),
            'at': to_iso(order.date_order), 'amount': round(order.amount_total, 2),
            'lat': order.ff_latitude, 'lng': order.ff_longitude,
            'photos': [], 'note': '', 'res_id': order.id,
        } for order in orders]

    def _form_events(self, employee, start, end):
        if 'ff.form.response' not in self.env:
            return []
        responses = self.env['ff.form.response'].sudo().search([
            ('employee_id', '=', employee.id), ('submitted_at', '>=', start), ('submitted_at', '<', end)])
        return [{
            'kind': 'form', 'title': response.form_id.name,
            'at': to_iso(response.submitted_at), 'photos': [], 'note': response.partner_id.display_name or '',
            'lat': 0.0, 'lng': 0.0, 'res_id': response.id,
        } for response in responses]

    def _expense_events(self, employee, start, end):
        if 'ff.expense.claim' not in self.env:
            return []
        claims = self.env['ff.expense.claim'].sudo().search([
            ('employee_id', '=', employee.id), ('date', '=', start.date())])
        return [{
            'kind': 'expense', 'title': claim.category_id.name or 'Expense',
            'at': to_iso(claim.create_date), 'amount': round(claim.amount, 2),
            'photos': self._photos('ff.expense.claim', claim.id),
            'note': claim.note or '', 'lat': 0.0, 'lng': 0.0, 'res_id': claim.id,
        } for claim in claims]

    def _collection_events(self, employee, start, end):
        if 'ff.collection' not in self.env:
            return []
        collections = self.env['ff.collection'].sudo().search([
            ('employee_id', '=', employee.id), ('date', '>=', start), ('date', '<', end)])
        return [{
            'kind': 'collection',
            'title': '%s from %s' % (collection.mode_id.name, collection.partner_id.display_name),
            'at': to_iso(collection.date), 'amount': round(collection.amount, 2),
            'photos': self._photos('ff.collection', collection.id),
            'note': collection.reference or '', 'lat': collection.latitude, 'lng': collection.longitude,
            'res_id': collection.id,
        } for collection in collections]

    def _photos(self, model, res_id):
        attachments = self.env['ir.attachment'].sudo().search(
            [('res_model', '=', model), ('res_id', '=', res_id)], limit=4)
        return ['/web/image/%s' % attachment.id for attachment in attachments]

    def _with_travel(self, events, pings):
        """Insert the travel between two stops, with the distance actually walked."""
        if not pings:
            return events
        points = [(ping.ts, ping.latitude, ping.longitude, ping.accuracy) for ping in pings]
        told = []
        previous = None
        for event in events:
            if previous and previous.get('at') and event.get('at'):
                leg = [point for point in points
                       if previous['at'] <= to_iso(point[0]) <= event['at']]
                distance = path_distance_km(leg)
                minutes = self._minutes_between(previous['at'], event['at'])
                if distance >= 0.1 or minutes >= 10:
                    told.append({
                        'kind': 'travel',
                        'title': 'Travel',
                        'at': previous['at'],
                        'distance_km': round(distance, 2),
                        'minutes': minutes,
                        'photos': [],
                    })
            told.append(event)
            previous = event
        return told

    def _minutes_between(self, first, second):
        start = fields.Datetime.to_datetime(first.replace('T', ' ').split('+')[0].replace('Z', ''))
        end = fields.Datetime.to_datetime(second.replace('T', ' ').split('+')[0].replace('Z', ''))
        return int((end - start).total_seconds() // 60) if start and end else 0

    def _straight_km(self, first, second):
        return round(haversine_m(first[1], first[2], second[1], second[2]) / 1000.0, 2)
