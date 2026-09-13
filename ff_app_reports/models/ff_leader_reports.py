"""Reports a team leader reads: who sold and collected what, where, which products,
who is working today, who is on top, route plans and order sizes.

They run for the same people and dates as every app report - "me", "me and my
team" or one person - so a leader only ever sees their own branch.
"""
from collections import defaultdict
from datetime import timedelta

from odoo import models

from .ff_app_report import DATE, HOURS, KM, MONEY, NUMBER, STATUS, TIME, col

# Order size bands for the "orders by value" report.
BANDS = [(0, 1000, 'Below 1K'), (1000, 5000, '1K – 5K'), (5000, 25000, '5K – 25K'),
         (25000, 100000, '25K – 1L'), (100000, None, '1L and above')]


class FfLeaderReports(models.AbstractModel):
    _inherit = 'ff.app.report'

    def _definitions(self):
        defs = super()._definitions()
        sale_word = 'Demand' if self._demand_flow() else 'Sales'
        defs.update({
            'employee_sales': ('%s by employee' % sale_word, 'Value, count and outlets per person', 'leaderboard',
                               self._sales_model(), [
                col('employee', 'Employee'), col('count', 'Orders', NUMBER, True), col('outlets', 'Outlets', NUMBER, True),
                col('amount', 'Value', MONEY, True), col('average', 'Average', MONEY)], self._employee_sales),
            'employee_collections': ('Collections by employee', 'Cash, online and cheque per person', 'account_balance_wallet',
                                     'ff.collection', [
                col('employee', 'Employee'), col('count', 'Payments', NUMBER, True), col('cash', 'Cash', MONEY, True),
                col('online', 'Online', MONEY, True), col('cheque', 'Cheque / PDC', MONEY, True),
                col('pending', 'Not deposited', MONEY, True), col('amount', 'Total', MONEY, True)], self._employee_collections),
            'customer_sales': ('Customer %s & collections' % sale_word.lower(), 'What each customer bought and paid',
                               'storefront', self._sales_model(), [
                col('customer', 'Customer'), col('city', 'City'), col('orders', 'Orders', NUMBER, True),
                col('sales', sale_word, MONEY, True), col('collected', 'Collected', MONEY, True),
                col('difference', 'Not collected', MONEY, True), col('last_visit', 'Last visit', DATE)], self._customer_sales),
            'product_sales': ('Product-wise %s' % sale_word.lower(), 'Quantity and value per product', 'inventory_2',
                              self._sales_model(), [
                col('product', 'Product'), col('sku', 'SKU'), col('quantity', 'Quantity', NUMBER, True),
                col('outlets', 'Outlets', NUMBER), col('amount', 'Value', MONEY, True)], self._product_sales),
            'top_products': ('Top 10 products', 'Best sellers by value', 'star', self._sales_model(), [
                col('rank', '#', NUMBER), col('product', 'Product'), col('quantity', 'Quantity', NUMBER, True),
                col('amount', 'Value', MONEY, True), col('share', 'Share %', NUMBER)], self._top_products),
            'today_team': ('Working & on leave', 'Who is working, on leave or absent (last day of the period)', 'groups',
                           'hr.attendance', [
                col('employee', 'Employee'), col('status', 'Status', STATUS), col('check_in', 'In', TIME),
                col('check_out', 'Out', TIME), col('hours', 'Hours', HOURS, True), col('visits', 'Visits', NUMBER, True),
                col('note', 'Leave / note')], self._today_team),
            'top_performers': ('Top performers', 'Ranked on sales, collections, visits and new customers', 'emoji_events',
                               'ff.visit', [
                col('rank', '#', NUMBER), col('employee', 'Employee'), col('score', 'Score', NUMBER),
                col('sales', sale_word, MONEY, True), col('collections', 'Collected', MONEY, True),
                col('visits', 'Visits', NUMBER, True), col('customers', 'New customers', NUMBER, True)], self._top_performers),
            'order_values': ('%s by order value' % sale_word, 'Every order with its size band, largest first', 'sort',
                             self._sales_model(), [
                col('date', 'Date', DATE), col('number', 'Number'), col('employee', 'Employee'), col('customer', 'Customer'),
                col('band', 'Band'), col('amount', 'Value', MONEY, True)], self._order_values),
            'expense_summary': ('Expenses by employee', 'Claimed per person and type', 'receipt_long', 'ff.expense.claim', [
                col('employee', 'Employee'), col('category', 'Type'), col('count', 'Claims', NUMBER, True),
                col('amount', 'Claimed', MONEY, True), col('approved', 'Approved', MONEY, True),
                col('waiting', 'Waiting', MONEY, True)], self._expense_summary),
            'team_summary': ('Summary by employee', 'One line per person: days, hours, visits, sales, collections, km',
                             'summarize', 'hr.attendance', [
                col('employee', 'Employee'), col('days', 'Days worked', NUMBER, True), col('hours', 'Hours', HOURS, True),
                col('late', 'Late days', NUMBER, True), col('visits', 'Visits', NUMBER, True),
                col('offsite', 'Offsite', NUMBER, True), col('orders', '%s count' % sale_word, NUMBER, True),
                col('sales', sale_word, MONEY, True), col('collections', 'Collected', MONEY, True),
                col('expenses', 'Expenses', MONEY, True), col('customers', 'New customers', NUMBER, True),
                col('km', 'Distance', KM, True)], self._team_summary),
            'daily_summary': ('Summary by day', 'One line per day for the people chosen', 'calendar_month',
                              'hr.attendance', [
                col('date', 'Date', DATE), col('present', 'Present', NUMBER, True), col('hours', 'Hours', HOURS, True),
                col('visits', 'Visits', NUMBER, True), col('orders', '%s count' % sale_word, NUMBER, True),
                col('sales', sale_word, MONEY, True), col('collections', 'Collected', MONEY, True),
                col('expenses', 'Expenses', MONEY, True), col('km', 'Distance', KM, True)], self._daily_summary),
            'route_plans': ('Route plans', 'Planned routes per person and how they went', 'alt_route', 'ff.beat.plan', [
                col('date', 'Date', DATE), col('employee', 'Employee'), col('route', 'Route'),
                col('planned', 'Planned', NUMBER, True), col('visited', 'Visited', NUMBER, True),
                col('missed', 'Missed', NUMBER, True), col('completion', 'Done %', NUMBER),
                col('km', 'Actual km', KM, True)], self._route_plans),
        })
        return {key: value for key, value in defs.items() if value[3] in self.env}

    # ------------------------------------------------------------------
    # Sales, whichever flow the company is on
    # ------------------------------------------------------------------
    def _demand_flow(self):
        return self._order_flow() == 'demand' and 'ff.demand' in self.env

    def _sales_model(self):
        return 'ff.demand' if self._demand_flow() else 'sale.order'

    def _sales_docs(self, employees, start, end):
        """[(employee, partner, date, number, amount, [(product, quantity, value)])] in the period."""
        low, high = self._utc_bounds(start, end)
        docs = []
        if self._demand_flow():
            for d in self.env['ff.demand'].sudo().search([
                    ('employee_id', 'in', employees.ids), ('date', '>=', low), ('date', '<', high),
                    ('state', '!=', 'cancelled')], order='date desc'):
                docs.append((d.employee_id, d.partner_id, d.date, d.name, d.amount_total,
                             [(l.product_id, l.quantity, l.subtotal) for l in d.line_ids if l.product_id]))
        else:
            company = self._viewer().company_id
            for o in self.env['sale.order'].sudo().search([
                    ('ff_employee_id', 'in', employees.ids), ('date_order', '>=', low), ('date_order', '<', high),
                    ('state', '!=', 'cancel')], order='date_order desc'):
                rate = o.currency_id._convert(1.0, company.currency_id, company, o.date_order.date()) \
                    if o.currency_id != company.currency_id else 1.0
                docs.append((o.ff_employee_id, o.partner_id, o.date_order, o.name, o.amount_total * rate,
                             [(l.product_id, l.product_uom_qty, l.price_subtotal * rate) for l in o.order_line if l.product_id]))
        return docs

    # ------------------------------------------------------------------
    def _employee_sales(self, employees, start, end):
        rows = {}
        for employee, partner, _date, _number, amount, _lines in self._sales_docs(employees, start, end):
            row = rows.setdefault(employee.id, {'employee': employee.name, 'count': 0, 'amount': 0.0, '_outlets': set()})
            row['count'] += 1
            row['amount'] += amount
            row['_outlets'].add(partner.commercial_partner_id.id)
        result = []
        for row in sorted(rows.values(), key=lambda r: -r['amount']):
            outlets = row.pop('_outlets')
            result.append(dict(row, amount=round(row['amount'], 2), outlets=len(outlets),
                               average=round(row['amount'] / row['count'], 2) if row['count'] else 0.0))
        return result

    def _employee_collections(self, employees, start, end):
        low, high = self._utc_bounds(start, end)
        rows = {}
        for c in self.env['ff.collection'].sudo().search([
                ('employee_id', 'in', employees.ids), ('date', '>=', low), ('date', '<', high),
                ('state', '!=', 'cancelled')]):
            row = rows.setdefault(c.employee_id.id, {'employee': c.employee_id.name, 'count': 0, 'cash': 0.0,
                                                     'online': 0.0, 'cheque': 0.0, 'pending': 0.0, 'amount': 0.0})
            row['count'] += 1
            row['amount'] += c.amount
            kind = c.mode_type or 'cash'
            bucket = 'cash' if kind == 'cash' else 'cheque' if kind in ('cheque', 'pdc') else 'online'
            row[bucket] += c.amount
            if c.state in ('collected', 'submitted'):
                row['pending'] += c.amount
        return sorted(({k: (round(v, 2) if isinstance(v, float) else v) for k, v in row.items()} for row in rows.values()),
                      key=lambda r: -r['amount'])

    def _customer_sales(self, employees, start, end):
        rows = {}

        def row_for(partner):
            family = partner.commercial_partner_id
            return rows.setdefault(family.id, {'customer': family.display_name, 'city': family.city or '',
                                               'orders': 0, 'sales': 0.0, 'collected': 0.0,
                                               'last_visit': family.ff_last_visit_at.date().isoformat()
                                               if family.ff_last_visit_at else None})

        for _employee, partner, _date, _number, amount, _lines in self._sales_docs(employees, start, end):
            row = row_for(partner)
            row['orders'] += 1
            row['sales'] += amount
        if 'ff.collection' in self.env:
            low, high = self._utc_bounds(start, end)
            for c in self.env['ff.collection'].sudo().search([
                    ('employee_id', 'in', employees.ids), ('date', '>=', low), ('date', '<', high),
                    ('state', '!=', 'cancelled')]):
                row_for(c.partner_id)['collected'] += c.amount
        result = []
        for row in rows.values():
            row['sales'] = round(row['sales'], 2)
            row['collected'] = round(row['collected'], 2)
            row['difference'] = round(max(row['sales'] - row['collected'], 0.0), 2)
            result.append(row)
        return sorted(result, key=lambda r: -(r['sales'] + r['collected']))

    def _product_totals(self, employees, start, end):
        rows = {}
        for _employee, partner, _date, _number, _amount, lines in self._sales_docs(employees, start, end):
            for product, quantity, value in lines:
                row = rows.setdefault(product.id, {'product': product.display_name,
                                                   'sku': product.default_code or '', 'quantity': 0.0,
                                                   'amount': 0.0, '_outlets': set()})
                row['quantity'] += quantity
                row['amount'] += value
                row['_outlets'].add(partner.commercial_partner_id.id)
        result = []
        for row in rows.values():
            outlets = row.pop('_outlets')
            result.append(dict(row, quantity=round(row['quantity'], 2), amount=round(row['amount'], 2),
                               outlets=len(outlets)))
        return sorted(result, key=lambda r: -r['amount'])

    def _product_sales(self, employees, start, end):
        return self._product_totals(employees, start, end)

    def _top_products(self, employees, start, end):
        rows = self._product_totals(employees, start, end)
        total = sum(r['amount'] for r in rows) or 1.0
        return [{'rank': i, 'product': r['product'], 'quantity': r['quantity'], 'amount': r['amount'],
                 'share': round(r['amount'] * 100.0 / total, 1)} for i, r in enumerate(rows[:10], 1)]

    def _today_team(self, employees, start, end):
        """The last day of the period: present (with times), on leave, or absent."""
        day = end
        low, high = self._utc_bounds(day, day)
        attendances = defaultdict(lambda: self.env['hr.attendance'])
        for att in self.env['hr.attendance'].sudo().search([
                ('employee_id', 'in', employees.ids), ('check_in', '>=', low - timedelta(hours=12)), ('check_in', '<', high)],
                order='check_in'):
            if self._local(att.employee_id, att.check_in).date() == day:
                attendances[att.employee_id.id] |= att
        leaves = {}
        if 'hr.leave' in self.env:
            for leave in self.env['hr.leave'].sudo().search([
                    ('employee_id', 'in', employees.ids), ('state', 'in', ('validate', 'validate1', 'confirm')),
                    ('request_date_from', '<=', day), ('request_date_to', '>=', day)]):
                leaves[leave.employee_id.id] = leave
        visits = defaultdict(int)
        for visit in self.env['ff.visit'].sudo().search([
                ('employee_id', 'in', employees.ids), ('check_in_at', '>=', low), ('check_in_at', '<', high)]):
            visits[visit.employee_id.id] += 1
        order = {'Working': 0, 'Checked out': 1, 'On leave': 2, 'Leave requested': 3, 'Absent': 4}
        rows = []
        for employee in employees:
            atts = attendances.get(employee.id)
            leave = leaves.get(employee.id)
            if atts:
                last = atts[-1]
                status = 'Checked out' if last.check_out else 'Working'
                rows.append({
                    'employee': employee.name, 'status': status,
                    'check_in': self._local(employee, atts[0].check_in).strftime('%H:%M'),
                    'check_out': self._local(employee, last.check_out).strftime('%H:%M') if last.check_out else None,
                    'hours': round(sum(atts.mapped('worked_hours')), 2), 'visits': visits[employee.id], 'note': '',
                })
            else:
                status = ('On leave' if leave.state == 'validate' else 'Leave requested') if leave else 'Absent'
                rows.append({'employee': employee.name, 'status': status, 'check_in': None, 'check_out': None,
                             'hours': 0.0, 'visits': visits[employee.id],
                             'note': leave.holiday_status_id.name if leave else ''})
        return sorted(rows, key=lambda r: (order.get(r['status'], 9), r['employee']))

    def _top_performers(self, employees, start, end):
        if 'ff.target' in self.env:
            actuals = self.env['ff.target'].ff_actuals(employees, start, end)
        else:
            actuals = {e.id: {'visits': 0, 'customers': 0, 'sales': 0.0, 'collections': 0.0} for e in employees}
        names = {e.id: e.name for e in employees}
        best = {key: max((row[key] for row in actuals.values()), default=0) or 1
                for key in ('visits', 'customers', 'sales', 'collections')}
        weights = {'sales': 40, 'collections': 30, 'visits': 20, 'customers': 10}
        rows = []
        for employee_id, row in actuals.items():
            score = sum(weights[key] * row[key] / best[key] for key in weights)
            rows.append({'employee': names[employee_id], 'score': round(score), 'sales': round(row['sales'], 2),
                         'collections': round(row['collections'], 2), 'visits': row['visits'],
                         'customers': row['customers']})
        rows.sort(key=lambda r: (-r['score'], -r['sales']))
        for rank, row in enumerate(rows, 1):
            row['rank'] = rank
        return [r for r in rows if r['score'] > 0] or rows

    def _order_values(self, employees, start, end):
        rows = []
        for employee, partner, date, number, amount, _lines in self._sales_docs(employees, start, end):
            band = next(label for low, high, label in BANDS if amount >= low and (high is None or amount < high))
            rows.append({'date': self._local(employee, date).date().isoformat(), 'number': number,
                         'employee': employee.name, 'customer': partner.display_name, 'band': band,
                         'amount': round(amount, 2)})
        return sorted(rows, key=lambda r: -r['amount'])

    def _expense_summary(self, employees, start, end):
        rows = {}
        for claim in self.env['ff.expense.claim'].sudo().search([
                ('employee_id', 'in', employees.ids), ('date', '>=', start), ('date', '<=', end)]):
            key = (claim.employee_id.id, claim.category_id.id)
            row = rows.setdefault(key, {'employee': claim.employee_id.name, 'category': claim.category_id.name,
                                        'count': 0, 'amount': 0.0, 'approved': 0.0, 'waiting': 0.0})
            row['count'] += 1
            row['amount'] += claim.amount
            if claim.state == 'approved':
                row['approved'] += claim.amount
            elif claim.state == 'submitted':
                row['waiting'] += claim.amount
        return sorted(({k: (round(v, 2) if isinstance(v, float) else v) for k, v in row.items()} for row in rows.values()),
                      key=lambda r: (r['employee'], -r['amount']))

    def _route_plans(self, employees, start, end):
        plans = self.env['ff.beat.plan'].sudo().search([
            ('employee_id', 'in', employees.ids), ('date', '>=', start), ('date', '<=', end)], order='date desc, employee_id')
        return [{
            'date': plan.date.isoformat(), 'employee': plan.employee_id.name, 'route': plan.beat_id.display_name,
            'planned': plan.planned_count, 'visited': plan.completed_count, 'missed': plan.missed_count,
            'completion': round(plan.completion_pct, 1), 'km': round(plan.actual_km or 0.0, 1),
        } for plan in plans]

    # ------------------------------------------------------------------
    # Summaries
    # ------------------------------------------------------------------
    def _summary_facts(self, employees, start, end):
        """(employee id, local day) -> counters for everything a summary adds up."""
        facts = defaultdict(lambda: defaultdict(float))
        low, high = self._utc_bounds(start, end)
        for att in self.env['hr.attendance'].sudo().search([
                ('employee_id', 'in', employees.ids), ('check_in', '>=', low), ('check_in', '<', high)]):
            key = (att.employee_id.id, self._local(att.employee_id, att.check_in).date())
            facts[key]['present'] = 1
            facts[key]['hours'] += att.worked_hours or 0.0
            if 'ff_day_status' in att._fields and att.ff_day_status == 'late':
                facts[key]['late'] = 1
        for visit in self.env['ff.visit'].sudo().search([
                ('employee_id', 'in', employees.ids), ('check_in_at', '>=', low), ('check_in_at', '<', high)]):
            key = (visit.employee_id.id, self._local(visit.employee_id, visit.check_in_at).date())
            facts[key]['visits'] += 1
            if 'visit_type' in visit._fields and visit.visit_type == 'offsite':
                facts[key]['offsite'] += 1
        for employee, _partner, date, _number, amount, _lines in self._sales_docs(employees, start, end):
            key = (employee.id, self._local(employee, date).date())
            facts[key]['orders'] += 1
            facts[key]['sales'] += amount
        if 'ff.collection' in self.env:
            for c in self.env['ff.collection'].sudo().search([
                    ('employee_id', 'in', employees.ids), ('date', '>=', low), ('date', '<', high),
                    ('state', '!=', 'cancelled')]):
                facts[(c.employee_id.id, self._local(c.employee_id, c.date).date())]['collections'] += c.amount
        if 'ff.expense.claim' in self.env:
            for claim in self.env['ff.expense.claim'].sudo().search([
                    ('employee_id', 'in', employees.ids), ('date', '>=', start), ('date', '<=', end),
                    ('state', '!=', 'rejected')]):
                facts[(claim.employee_id.id, claim.date)]['expenses'] += claim.amount
        for partner in self.env['res.partner'].sudo().with_context(active_test=False).search([
                ('ff_created_by_employee_id', 'in', employees.ids), ('create_date', '>=', low),
                ('create_date', '<', high)]):
            employee = partner.ff_created_by_employee_id
            facts[(employee.id, self._local(employee, partner.create_date).date())]['customers'] += 1
        for track in self.env['ff.daily.track'].sudo().search([
                ('employee_id', 'in', employees.ids), ('date', '>=', start), ('date', '<=', end)]):
            facts[(track.employee_id.id, track.date)]['km'] += track.distance_km
        return facts

    @staticmethod
    def _round_row(row):
        return {k: (round(v, 2) if isinstance(v, float) else v) for k, v in row.items()}

    def _team_summary(self, employees, start, end):
        facts = self._summary_facts(employees, start, end)
        rows = []
        for employee in employees.sorted('name'):
            total = defaultdict(float)
            for (employee_id, _day), values in facts.items():
                if employee_id == employee.id:
                    for key, value in values.items():
                        total[key] += value
            rows.append(self._round_row({
                'employee': employee.name, 'days': int(total['present']), 'hours': total['hours'],
                'late': int(total['late']), 'visits': int(total['visits']), 'offsite': int(total['offsite']),
                'orders': int(total['orders']), 'sales': total['sales'], 'collections': total['collections'],
                'expenses': total['expenses'], 'customers': int(total['customers']), 'km': total['km'],
            }))
        return sorted(rows, key=lambda r: -r['sales'])

    def _daily_summary(self, employees, start, end):
        facts = self._summary_facts(employees, start, end)
        rows = []
        day = end
        while day >= start:
            total = defaultdict(float)
            for (_employee_id, fact_day), values in facts.items():
                if fact_day == day:
                    for key, value in values.items():
                        total[key] += value
            rows.append(self._round_row({
                'date': day.isoformat(), 'present': int(total['present']), 'hours': total['hours'],
                'visits': int(total['visits']), 'orders': int(total['orders']), 'sales': total['sales'],
                'collections': total['collections'], 'expenses': total['expenses'], 'km': total['km'],
            }))
            day -= timedelta(days=1)
        return rows
