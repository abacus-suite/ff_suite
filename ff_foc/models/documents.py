"""FOC on the documents the field raises: orders and demands get their free
lines at ₹0, the distributor quotation keeps them apart, and a report counts
what was given away."""
from odoo import api, fields, models
from odoo.exceptions import UserError

from odoo.addons.ff_app_reports.models.ff_app_report import DATE, MONEY, NUMBER, col


def manual_allowed(env):
    return env['ir.config_parameter'].sudo().get_param('ff_foc.manual_allowed', 'True') != 'False'


def _manual_rows(env, data):
    """Free units the rep added by hand (samples, trade FOC), with their reason."""
    rows = []
    for item in data.get('foc') or []:
        try:
            quantity = float(item.get('qty') or 0)
        except (TypeError, ValueError):
            continue
        if quantity <= 0:
            continue
        if not manual_allowed(env):
            raise UserError(env._('Free goods can only come from a scheme.'))
        reason = (item.get('reason') or '').strip()
        if not reason:
            raise UserError(env._('Give a reason for the free goods.'))
        product = env['product.product'].sudo().browse(int(item.get('product_id') or 0)).exists()
        if not product:
            raise UserError(env._('Free product %s was not found.', item.get('product_id')))
        rows.append({'product': product, 'quantity': quantity, 'reason': reason[:120]})
    return rows


class SaleOrderLine(models.Model):
    _inherit = 'sale.order.line'

    ff_is_foc = fields.Boolean(string='FOC', index=True, copy=False)
    ff_foc_scheme_id = fields.Many2one('ff.foc.scheme', string='FOC Scheme', ondelete='set null', copy=False)
    ff_foc_reason = fields.Char(string='FOC Reason', copy=False)


class SaleOrder(models.Model):
    _inherit = 'sale.order'

    ff_foc_value = fields.Monetary(string='FOC Value', compute='_compute_ff_foc_value',
                                   help='What the free lines are worth at the field price.')

    @api.depends('order_line.ff_is_foc', 'order_line.product_uom_qty')
    def _compute_ff_foc_value(self):
        for order in self:
            order.ff_foc_value = sum(line.product_uom_qty * line.product_id.ff_field_price()
                                     for line in order.order_line if line.ff_is_foc)

    @api.model
    def ff_create_from_app(self, employee, partner, data):
        order = super().ff_create_from_app(employee, partner, data)
        if order.order_line.filtered('ff_is_foc'):
            return order  # a resent order: its free lines are already there
        paid = [(line.product_id, line.product_uom_qty) for line in order.order_line if line.product_id]
        lines = []
        for row in self.env['ff.foc.scheme'].ff_compute(employee, partner, paid):
            lines.append((0, 0, {'product_id': row['product'].id, 'product_uom_qty': row['quantity'],
                                 'price_unit': 0.0, 'ff_is_foc': True, 'ff_foc_scheme_id': row['scheme'].id,
                                 'name': '%s (FOC - %s)' % (row['product'].display_name, row['scheme'].name)}))
        for row in _manual_rows(self.env, data):
            lines.append((0, 0, {'product_id': row['product'].id, 'product_uom_qty': row['quantity'],
                                 'price_unit': 0.0, 'ff_is_foc': True, 'ff_foc_reason': row['reason'],
                                 'name': '%s (FOC - %s)' % (row['product'].display_name, row['reason'])}))
        if lines:
            order.sudo().write({'order_line': lines})
        return order


class FfDemandLine(models.Model):
    _inherit = 'ff.demand.line'

    is_foc = fields.Boolean(string='FOC', index=True)
    foc_scheme_id = fields.Many2one('ff.foc.scheme', string='FOC Scheme', ondelete='set null')
    foc_reason = fields.Char(string='FOC Reason')

    @property
    def pending_quantity(self):
        quantity = max(self.quantity - self.quoted_quantity, 0.0)
        flag = self.env.context.get('ff_foc_settle')
        if flag is not None and bool(self.is_foc) != flag:
            return 0.0  # while settling the other kind, this line is not available
        return quantity


class FfDemand(models.Model):
    _inherit = 'ff.demand'

    foc_value = fields.Monetary(string='FOC Value', compute='_compute_foc_value')

    @api.depends('line_ids.is_foc', 'line_ids.quantity')
    def _compute_foc_value(self):
        for demand in self:
            demand.foc_value = sum(line.quantity * line.product_id.ff_field_price()
                                   for line in demand.line_ids if line.is_foc)

    @api.model
    def ff_create_from_app(self, employee, partner, data):
        demand = super().ff_create_from_app(employee, partner, data)
        if demand.line_ids.filtered('is_foc'):
            return demand
        paid = [(line.product_id, line.quantity) for line in demand.line_ids]
        lines = [(0, 0, {'product_id': row['product'].id, 'quantity': row['quantity'], 'price_unit': 0.0,
                         'is_foc': True, 'foc_scheme_id': row['scheme'].id})
                 for row in self.env['ff.foc.scheme'].ff_compute(employee, partner, paid)]
        lines += [(0, 0, {'product_id': row['product'].id, 'quantity': row['quantity'], 'price_unit': 0.0,
                          'is_foc': True, 'foc_reason': row['reason']})
                  for row in _manual_rows(self.env, data)]
        if lines:
            demand.sudo().write({'line_ids': lines})
        return demand


class FfDemandQuotationLine(models.TransientModel):
    _inherit = 'ff.demand.quotation.line'

    is_foc = fields.Boolean(string='FOC', readonly=True)


class FfDemandQuotation(models.TransientModel):
    _inherit = 'ff.demand.quotation'

    def _consolidate(self, demands):
        """Paid and free quantities of a product stay on separate rows; free rows are priced at zero."""
        rows = {}
        for line in demands.mapped('line_ids'):
            pending = line.pending_quantity
            if pending <= 0:
                continue
            key = (line.demand_id.distributor_id.id, line.product_id.id, line.is_foc)
            row = rows.setdefault(key, {
                'distributor_id': line.demand_id.distributor_id.id,
                'product_id': line.product_id.id,
                'quantity': 0.0,
                'outlets': 0,
                'price_unit': 0.0 if line.is_foc else line.product_id.ff_distributor_price(),
                'is_foc': line.is_foc,
            })
            row['quantity'] += pending
            row['outlets'] += 1
        return sorted(rows.values(), key=lambda row: (row['distributor_id'] or 0, row['product_id'], row['is_foc']))

    def _settle(self, order, rows, distributor):
        """Settle free rows against free demand lines, paid against paid."""
        for flag in (False, True):
            chosen = rows.filtered(lambda row, flag=flag: row.is_foc == flag)
            if not chosen:
                continue
            super(FfDemandQuotation, self.with_context(ff_foc_settle=flag))._settle(order, chosen, distributor)

    def action_create(self):
        result = super().action_create()
        # The order lines the base wizard created carry no FOC mark: find the zero-priced ones from FOC rows.
        orders = self.env['sale.order'].browse((result or {}).get('domain', [[None, None, []]])[0][2])
        foc_products = {(row.product_id.id) for row in self.line_ids if row.is_foc}
        for line in orders.order_line.filtered(lambda l: l.product_id.id in foc_products and not l.price_unit):
            line.write({'ff_is_foc': True, 'name': '%s (FOC)' % line.product_id.display_name})
        return result


class FfAppReportFoc(models.AbstractModel):
    _inherit = 'ff.app.report'

    def _definitions(self):
        defs = super()._definitions()
        defs['foc'] = ('FOC given', 'Free goods by scheme or reason, with their value', 'redeem',
                       'ff.demand' if self._order_flow() == 'demand' else 'sale.order', [
            col('date', 'Date', DATE), col('employee', 'Employee'), col('customer', 'Customer'),
            col('document', 'Order / demand'), col('product', 'Product'), col('quantity', 'Free qty', NUMBER, True),
            col('value', 'Value', MONEY, True), col('why', 'Scheme / reason')], self._foc)
        return defs

    def _foc(self, employees, start, end):
        low, high = self._utc_bounds(start, end)
        rows = []
        if self._order_flow() == 'demand' and 'ff.demand' in self.env:
            lines = self.env['ff.demand.line'].sudo().search([
                ('is_foc', '=', True), ('employee_id', 'in', employees.ids), ('date', '>=', low), ('date', '<', high),
                ('state', '!=', 'cancelled')], order='date desc')
            for line in lines:
                rows.append({'date': self._local(line.employee_id, line.date).date().isoformat(),
                             'employee': line.employee_id.name, 'customer': line.partner_id.display_name,
                             'document': line.demand_id.name, 'product': line.product_id.display_name,
                             'quantity': line.quantity, 'value': round(line.quantity * line.product_id.ff_field_price(), 2),
                             'why': line.foc_scheme_id.name or line.foc_reason or ''})
        else:
            lines = self.env['sale.order.line'].sudo().search([
                ('ff_is_foc', '=', True), ('order_id.ff_employee_id', 'in', employees.ids),
                ('order_id.date_order', '>=', low), ('order_id.date_order', '<', high),
                ('order_id.state', '!=', 'cancel')])
            for line in lines:
                order = line.order_id
                rows.append({'date': self._local(order.ff_employee_id, order.date_order).date().isoformat(),
                             'employee': order.ff_employee_id.name, 'customer': order.partner_id.display_name,
                             'document': order.name, 'product': line.product_id.display_name,
                             'quantity': line.product_uom_qty,
                             'value': round(line.product_uom_qty * line.product_id.ff_field_price(), 2),
                             'why': line.ff_foc_scheme_id.name or line.ff_foc_reason or ''})
        return rows
