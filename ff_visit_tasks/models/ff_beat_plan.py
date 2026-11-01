from odoo import api, fields, models


class FfBeatPlan(models.Model):
    _inherit = 'ff.beat.plan'

    @api.model
    def ff_add_customer(self, employee, partner, date):
        """Put one customer on a day, leaving everything else on it as it is.

        A follow-up is a promise to come back on a date, and the day it lands on
        may already have a plan. The planner replaces what is not ticked; this
        only adds.
        """
        day = self.sudo().search(
            [('employee_id', '=', employee.id), ('date', '=', date), ('beat_id', '=', False)], limit=1)
        if not day:
            day = self.sudo().create({'employee_id': employee.id, 'date': date})
        day._ff_sync_plan_month()
        line = day.customer_line_ids.filtered(lambda l: l.partner_id == partner)
        if line:
            line.write({'selected': True})
        else:
            self.env['ff.route.plan.customer'].sudo().create({
                'day_id': day.id, 'partner_id': partner.id, 'selected': True,
                'sequence': max(day.customer_line_ids.mapped('sequence') or [0]) + 10,
            })
        return day

    @api.model
    def ff_remove_customer(self, employee, partner, from_date=None):
        """Take a customer off every day still to come that has not been visited yet."""
        from_date = from_date or employee._ff_today()
        lines = self.env['ff.route.plan.customer'].sudo().search([
            ('partner_id', '=', partner.id), ('day_id.date', '>=', from_date),
            ('visit_id', '=', False), ('selected', '=', True),
        ])
        lines.write({'selected': False})
        return len(lines)
