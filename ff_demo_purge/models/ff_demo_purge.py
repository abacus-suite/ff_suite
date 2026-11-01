"""Removing the demo data the demo modules left behind.

Both demo modules build their world in Python, so nothing carries an external
id and uninstalling them takes nothing away: the employees, customers, visits
and a year of history stay exactly where they were. This clears them out.

Rather than list every model by hand - there are dozens, and the list would go
stale the moment a module is added - the sweep works from the demo people
themselves. Every model with a link to hr.employee is asked for its rows
belonging to a demo employee, and those go. What is left over is named: the
teams, beats, districts and products the demo data made, all of which carry
"(Demo)" in their name or sit on a demo team.

Nothing here guesses. A record is removed only when it points at a demo login,
a demo employee, a demo customer, or carries the demo marker in its own name,
so a database with real work in it beside the demo data keeps the real work.
"""
import logging

from odoo import api, fields, models

_logger = logging.getLogger(__name__)

# What the demo modules signed their work with.
DEMO_LOGIN_PREFIXES = ('demo.', 'sin.')
DEMO_EMAIL_DOMAIN = '@fieldforce.demo'
DEMO_NAME_MARKER = '(Demo)'

# Swept last, because everything else points at them.
MASTER_MODELS = (
    'ff.beat', 'ff.team', 'ff.district', 'ff.route.type', 'ff.designation',
    'ff.shift', 'ff.allowance.policy', 'ff.incentive.scheme', 'ff.foc.scheme',
    'ff.form', 'ff.visit.outcome', 'ff.visit.step.template', 'ff.collection.mode',
    'ff.expense.category', 'ff.target.template', 'hr.department', 'hr.leave.type',
    'product.category',
)

# Documents that refuse a plain unlink until they are put back into draft.
NEEDS_DRAFT = ('sale.order', 'account.move', 'account.payment', 'purchase.order')


class FfDemoPurge(models.TransientModel):
    """Find everything the demo modules made, say what it is, and remove it."""
    _name = 'ff.demo.purge'
    _description = 'Purge Demo Data'

    preview = fields.Text(string='What will be removed', readonly=True)
    removed = fields.Text(string='What was removed', readonly=True)
    done = fields.Boolean(readonly=True)

    @api.model
    def default_get(self, fields_list):
        values = super().default_get(fields_list)
        values['preview'] = self._ff_report(self._ff_survey())
        return values

    # ------------------------------------------------------------------
    # Finding the demo world
    # ------------------------------------------------------------------
    def _ff_demo_users(self):
        domain = ['|'] * (len(DEMO_LOGIN_PREFIXES))
        domain += [('login', '=like', '%s%%' % prefix) for prefix in DEMO_LOGIN_PREFIXES]
        domain += [('login', '=like', '%%%s' % DEMO_EMAIL_DOMAIN)]
        return self.env['res.users'].sudo().with_context(active_test=False).search(domain)

    def _ff_demo_employees(self):
        users = self._ff_demo_users()
        Employee = self.env['hr.employee'].sudo().with_context(active_test=False)
        found = Employee.search([('user_id', 'in', users.ids)]) if users else Employee
        # App-only demo staff have no Odoo user, but they do have the demo login.
        if 'ff_app_login' in Employee._fields:
            domain = ['|'] * (len(DEMO_LOGIN_PREFIXES) - 1)
            domain += [('ff_app_login', '=like', '%s%%' % prefix) for prefix in DEMO_LOGIN_PREFIXES]
            found |= Employee.search(domain)
        if 'work_email' in Employee._fields:
            found |= Employee.search([('work_email', '=like', '%%%s' % DEMO_EMAIL_DOMAIN)])
        found |= Employee.search([('name', 'like', DEMO_NAME_MARKER)])
        return found

    def _ff_demo_partners(self, employees):
        """Customers the demo made: by marker, by demo address, or added by demo staff."""
        Partner = self.env['res.partner'].sudo().with_context(active_test=False)
        found = Partner.search([('name', 'like', DEMO_NAME_MARKER)])
        found |= Partner.search([('email', '=like', '%%%s' % DEMO_EMAIL_DOMAIN)])
        if employees and 'ff_created_by_employee_id' in Partner._fields:
            found |= Partner.search([('ff_created_by_employee_id', 'in', employees.ids)])
        # Their children (delivery addresses and the like) go with them.
        if found:
            found |= Partner.search([('parent_id', 'in', found.ids)])
        # Never the company's own partner, nor a user's, nor anything with real work on it.
        companies = self.env['res.company'].sudo().search([]).partner_id
        keep = companies | self.env['res.users'].sudo().search(
            [('id', 'not in', self._ff_demo_users().ids)]).partner_id
        return found - keep

    def _ff_employee_models(self):
        """Every real model with a many2one to hr.employee, children before parents."""
        fields_ = self.env['ir.model.fields'].sudo().search([
            ('ttype', '=', 'many2one'), ('relation', '=', 'hr.employee'),
            ('store', '=', True),
        ])
        found = {}
        for field in fields_:
            model = self.env.get(field.model)
            if model is None or model._transient or model._abstract or not model._auto:
                continue
            if field.model in ('hr.employee', 'res.users', 'res.partner'):
                continue
            if field.name not in model._fields or model._fields[field.name].related:
                continue
            found.setdefault(field.model, set()).add(field.name)
        return found

    def _ff_survey(self):
        """Count what would go, without touching anything."""
        employees = self._ff_demo_employees()
        partners = self._ff_demo_partners(employees)
        users = self._ff_demo_users()
        counts = {}
        for model_name, field_names in self._ff_employee_models().items():
            if not employees:
                break
            records = self._ff_by_employee(model_name, field_names, employees)
            if records:
                counts[model_name] = len(records)
        for model_name in MASTER_MODELS:
            records = self._ff_masters(model_name, employees)
            if records:
                counts[model_name] = counts.get(model_name, 0) + len(records)
        products = self._ff_demo_products()
        if products:
            counts['product.template'] = len(products)
        if partners:
            counts['res.partner'] = len(partners)
        if employees:
            counts['hr.employee'] = len(employees)
        if users:
            counts['res.users'] = len(users)
        return counts

    def _ff_by_employee(self, model_name, field_names, employees):
        model = self.env[model_name].sudo().with_context(active_test=False)
        domain = ['|'] * (len(field_names) - 1)
        for name in sorted(field_names):
            domain.append((name, 'in', employees.ids))
        try:
            return model.search(domain)
        except Exception:
            return model.browse()

    def _ff_demo_products(self):
        """Products sitting in a demo category: the demo made both."""
        Category = self.env['product.category'].sudo()
        categories = Category.search([('name', 'like', DEMO_NAME_MARKER)])
        Template = self.env['product.template'].sudo().with_context(active_test=False)
        found = Template.search([('categ_id', 'in', categories.ids)]) if categories else Template
        found |= Template.search([('name', 'like', DEMO_NAME_MARKER)])
        return found

    def _ff_masters(self, model_name, employees):
        """Demo masters: marked by name, or belonging only to demo people."""
        model = self.env.get(model_name)
        if model is None:
            return self.env['ir.model'].browse()
        records = self.env[model_name].sudo().with_context(active_test=False)
        found = records
        if 'name' in records._fields:
            found |= records.search([('name', 'like', DEMO_NAME_MARKER)])
        if employees and 'employee_ids' in records._fields:
            # Only when every person on it is a demo person: a route the real
            # field also walks is not the demo module's to take away.
            shared = records.search([('employee_ids', 'in', employees.ids)])
            found |= shared.filtered(lambda r: r.employee_ids and not (r.employee_ids - employees))
        return found

    # ------------------------------------------------------------------
    # Removing it
    # ------------------------------------------------------------------
    def _ff_unlink(self, records, removed):
        """Delete what will go, one by one where the batch refuses."""
        records = records.exists()
        if not records:
            return
        model_name = records._name
        if model_name in NEEDS_DRAFT:
            self._ff_to_draft(records)
        try:
            with self.env.cr.savepoint():
                count = len(records)
                records.unlink()
                removed[model_name] = removed.get(model_name, 0) + count
                return
        except Exception:
            pass
        for record in records:
            try:
                with self.env.cr.savepoint():
                    record.unlink()
                    removed[model_name] = removed.get(model_name, 0) + 1
            except Exception as error:
                _logger.info('Demo purge: %s %s stays - %s', model_name, record.id, error)

    def _ff_to_draft(self, records):
        """A confirmed document cannot be deleted; put it back first."""
        for record in records:
            try:
                with self.env.cr.savepoint():
                    if hasattr(record, 'button_draft'):
                        record.button_draft()
                    if hasattr(record, 'action_cancel'):
                        record.action_cancel()
                    if 'state' in record._fields:
                        record.write({'state': 'draft'})
            except Exception:
                continue

    def action_purge(self):
        self.ensure_one()
        removed = self._ff_purge()
        self.write({'removed': self._ff_report(removed), 'done': True,
                    'preview': self._ff_report(self._ff_survey())})
        return {
            'type': 'ir.actions.act_window',
            'res_model': self._name,
            'res_id': self.id,
            'view_mode': 'form',
            'target': 'new',
        }

    @api.model
    def _ff_purge(self):
        """Remove the demo world. Safe to run again: it only ever finds less."""
        employees = self._ff_demo_employees()
        partners = self._ff_demo_partners(employees)
        users = self._ff_demo_users()
        removed = {}
        if not (employees or partners or users):
            _logger.info('Demo purge: nothing here to remove.')
            return removed

        # 1. Documents first, so nothing still points at a person or a customer.
        by_employee = self._ff_employee_models()
        for model_name in NEEDS_DRAFT:
            if model_name in by_employee:
                self._ff_unlink(self._ff_by_employee(model_name, by_employee.pop(model_name), employees), removed)
        for model_name, field_names in by_employee.items():
            if model_name in MASTER_MODELS:
                continue
            self._ff_unlink(self._ff_by_employee(model_name, field_names, employees), removed)

        # 2. Documents raised on a demo customer by somebody who is not demo staff.
        if partners:
            for model_name in NEEDS_DRAFT:
                model = self.env.get(model_name)
                if model is None or 'partner_id' not in self.env[model_name]._fields:
                    continue
                self._ff_unlink(
                    self.env[model_name].sudo().search([('partner_id', 'in', partners.ids)]), removed)

        # 3. The people. Before their partners: a user holds its own partner down.
        self._ff_unlink(employees, removed)
        self._ff_unlink(users, removed)

        # 4. The customers, and the products made to sell to them.
        self._ff_unlink(partners, removed)
        self._ff_unlink(self._ff_demo_products(), removed)

        # 5. The masters they were all built on.
        for model_name in MASTER_MODELS:
            self._ff_unlink(self._ff_masters(model_name, employees), removed)

        _logger.info('Demo purge removed: %s', removed or 'nothing')
        return removed

    def _ff_report(self, counts):
        if not counts:
            return self.env._('Nothing from the demo modules is left in this database.')
        lines = ['%-34s %6d' % (name, count) for name, count in sorted(counts.items())]
        lines.append('%-34s %6d' % ('TOTAL', sum(counts.values())))
        return '\n'.join(lines)
