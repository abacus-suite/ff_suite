from odoo import api, fields, models
from odoo.addons.ff_base.tools import parse_client_dt
from odoo.exceptions import UserError


def _num(value):
    try:
        return float(value)
    except (TypeError, ValueError):
        return None


class SaleOrder(models.Model):
    _inherit = 'sale.order'

    ff_source = fields.Selection([('backoffice', 'Back Office'), ('app', 'Field App')], string='Order Source',
                                 default='backoffice', index=True, copy=False)
    ff_employee_id = fields.Many2one('hr.employee', string='Field Employee', index=True, copy=False)
    ff_visit_id = fields.Many2one('ff.visit', string='Field Visit', copy=False)
    ff_latitude = fields.Float(string='Order Latitude', digits=(10, 7), copy=False)
    ff_longitude = fields.Float(string='Order Longitude', digits=(10, 7), copy=False)
    ff_client_uuid = fields.Char(index=True, copy=False)
    ff_outlet_id = fields.Many2one(
        'res.partner', string='Outlet', index=True, copy=False,
        help='The shop the order was taken at, when the order is billed to its distributor.')

    _ff_client_uuid_uniq = models.Constraint('UNIQUE(ff_client_uuid)', 'This field order was already received.')

    @api.model
    def ff_create_from_app(self, employee, partner, data):
        """Create a quotation from the field app. Idempotent on ``uuid``."""
        Order = self.sudo()
        uuid = data.get('uuid') or False
        if uuid:
            existing = Order.search([('ff_client_uuid', '=', uuid)], limit=1)
            if existing:
                return existing
        if partner.ff_approval_state != 'approved':
            raise UserError(self.env._('Orders can only be taken for approved clients.'))
        if partner.ff_category_id and not partner.ff_category_id.allow_orders:
            raise UserError(self.env._('Orders are not allowed for "%s" contacts.', partner.ff_category_id.name))

        Product = self.env['product.product'].sudo()
        line_vals = []
        for line in data.get('lines') or []:
            product_id, qty = line.get('product_id'), _num(line.get('qty'))
            if not qty or qty <= 0:
                continue
            product = Product.browse(int(product_id)).exists() if str(product_id).isdigit() else Product
            if not product or not product.sale_ok or not product.product_tmpl_id.ff_show_in_app:
                raise UserError(self.env._('Product %s is not available for field orders.', product_id))
            vals = {'product_id': product.id, 'product_uom_qty': qty}
            discount = _num(line.get('discount'))
            if discount:
                vals['discount'] = max(0.0, min(discount, 100.0))
            line_vals.append((0, 0, vals))
        if not line_vals:
            raise UserError(self.env._('Add at least one product to the order.'))

        visit = self.env['ff.visit'].sudo().search([
            ('employee_id', '=', employee.id), ('partner_id', '=', partner.id), ('state', '=', 'ongoing'),
        ], limit=1)
        # Sold through a distributor: the distributor is invoiced and the
        # outlet is kept, so everybody can still see where it was taken.
        billed_to = partner
        outlet = self.env['res.partner'].browse()
        if data.get('distributor_id'):
            distributor = self.env['res.partner'].sudo().browse(int(data['distributor_id'])).exists()
            if not distributor or not distributor.ff_is_distributor:
                raise UserError(self.env._('Choose a distributor from the list.'))
            billed_to, outlet = distributor, partner

        order = Order.create({
            'date_order': parse_client_dt(data.get('at')) or fields.Datetime.now(),
            'partner_id': billed_to.id,
            'partner_shipping_id': outlet.id or billed_to.id,
            'ff_outlet_id': outlet.id or False,
            'user_id': employee.user_id.id or False,
            'company_id': employee.company_id.id,
            'order_line': line_vals,
            'note': (data.get('note') or '').strip() or False,
            'ff_source': 'app',
            'ff_employee_id': employee.id,
            'ff_visit_id': visit.id or False,
            'ff_latitude': _num(data.get('lat')) or 0.0,
            'ff_longitude': _num(data.get('lng')) or 0.0,
            'ff_client_uuid': uuid,
        })
        if visit and not visit.outcome_id:
            order_outcome = self.env['ff.visit.outcome'].ff_for(employee, partner).filtered('is_order')[:1]
            visit.write({'outcome': 'order', 'outcome_id': order_outcome.id or False})
        return order
