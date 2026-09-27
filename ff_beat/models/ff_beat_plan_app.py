"""Planning a day from the field app.

Field staff plan their own week on the phone: pick a day, pick a route, and the
customers of that route come up already ticked with how long it has been since
each was visited. They untick what they will not reach and save.
"""
from odoo import api, fields, models
from odoo.exceptions import UserError


class FfBeatPlanApp(models.Model):
    _inherit = 'ff.beat.plan'

    @api.model
    def ff_app_routes(self, employee):
        """Routes this employee may plan.

        With shared contacts the whole field plans from every beat; otherwise
        they plan their own, and only fall back to all when they have none.
        """
        shared = self.env['res.partner']._ff_contact_access() == 'open'
        own = employee.sudo().ff_route_ids
        if shared or not own:
            routes = self.env['ff.beat'].sudo().search(
                [('company_id', 'in', (False, employee.company_id.id))])
            # Their own beats first: that is still where most of the work is.
            return (own | routes).sorted(lambda route: (route not in own, route.display_name))
        return own.sorted('display_name')

    @api.model
    def ff_app_route_customers(self, employee, route, date=None):
        """The customers of a route, in route order, with the day already planned
        (if any) deciding what is ticked."""
        route = route.sudo()
        day = self.sudo().search(
            [('employee_id', '=', employee.id), ('beat_id', '=', route.id), ('date', '=', date)], limit=1) if date else self.browse()
        chosen = {line.partner_id.id: line for line in day.customer_line_ids}
        customers = []
        for line in route.line_ids.sorted('sequence'):
            partner = line.partner_id
            existing = chosen.get(partner.id)
            customers.append({
                'partner': partner,
                'sequence': line.sequence,
                'selected': existing.selected if existing else True,
                'status': existing.status if existing else False,
                'visited': bool(existing and existing.visit_id),
            })
        return day, customers

    @api.model
    def ff_already_planned(self, employee, route, date):
        """Who else has this beat, or one of its customers, planned for that day.

        The same shop may well be called on by two people on the same day, so
        this only tells them; it never stands in the way.
        """
        if not date:
            return {'beat': [], 'customers': []}
        others = self.sudo().search([
            ('date', '=', date), ('employee_id', '!=', employee.id),
        ])
        same_beat = others.filtered(lambda day: day.beat_id == route)
        wanted = route.sudo().line_ids.partner_id
        customers = {}
        for day in others:
            for line in day.customer_line_ids:
                if not line.selected or line.partner_id not in wanted:
                    continue
                row = customers.setdefault(line.partner_id.id, {
                    'id': line.partner_id.id,
                    'name': line.partner_id.name,
                    'people': [],
                })
                if day.employee_id.name not in row['people']:
                    row['people'].append(day.employee_id.name)
        return {
            'beat': [{'id': day.employee_id.id, 'name': day.employee_id.name} for day in same_beat],
            'customers': list(customers.values()),
        }

    @api.model
    def ff_plan_from_app(self, employee, data):
        """Create or update one planned day. ``partner_ids`` are the customers the
        employee kept; everything else on the route is left out."""
        date = fields.Date.to_date(data.get('date')) or employee._ff_today()
        route = self.env['ff.beat'].sudo().browse(int(data.get('beat_id') or 0)).exists()
        if not route:
            raise UserError(self.env._('Choose a route to plan.'))
        shared = self.env['res.partner']._ff_contact_access() == 'open'
        allowed = employee.sudo().ff_route_ids
        if not shared and allowed and route not in allowed:
            raise UserError(self.env._('%s is not one of your routes.', route.display_name))
        if date < employee._ff_today():
            raise UserError(self.env._('A past day cannot be planned.'))

        kept = set(int(pid) for pid in (data.get('partner_ids') or []))
        route_partners = route.line_ids.sorted('sequence')
        if not route_partners:
            raise UserError(self.env._('%s has no customers yet.', route.display_name))

        day = self.sudo().search(
            [('employee_id', '=', employee.id), ('beat_id', '=', route.id), ('date', '=', date)], limit=1)
        if not day:
            day = self.sudo().create({'employee_id': employee.id, 'beat_id': route.id, 'date': date})
        day._ff_sync_plan_month()

        Line = self.env['ff.route.plan.customer'].sudo()
        existing = {line.partner_id.id: line for line in day.customer_line_ids}
        for route_line in route_partners:
            partner_id = route_line.partner_id.id
            selected = partner_id in kept
            line = existing.get(partner_id)
            if line:
                if line.visit_id:
                    continue  # already visited today; leave the history alone
                line.write({'selected': selected, 'sequence': route_line.sequence})
            elif selected:
                Line.create({
                    'day_id': day.id, 'partner_id': partner_id,
                    'sequence': route_line.sequence, 'selected': True,
                })
        return day

    def _ff_sync_plan_month(self):
        """Attach the day to the employee's monthly plan, creating it if needed, so
        the office sees app planning in the same place as its own."""
        Plan = self.env['ff.route.plan'].sudo()
        for day in self:
            if day.plan_id:
                continue
            month = day.date.replace(day=1)
            plan = Plan.search([('employee_id', '=', day.employee_id.id), ('month', '=', month)], limit=1)
            if not plan:
                plan = Plan.create({'employee_id': day.employee_id.id, 'month': month})
            day.plan_id = plan.id
