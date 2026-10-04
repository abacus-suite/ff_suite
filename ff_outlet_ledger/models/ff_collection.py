"""Where a collection ends up.

A salesperson collects money in two situations that look the same on the phone
and mean different things to the company:

* from an **outlet**, to be given to that outlet's distributor. It is the
  distributor's money, never the company's, so it is not something the
  salesperson owes the office and it must not appear among the cash waiting to
  be deposited.
* from a **distributor**, to be deposited with the company. That is the
  company's money, tied to the company's own invoices in Accounting.

Which one it is is recorded on the collection, because the rest follows from it.
"""
from odoo import api, fields, models
from odoo.exceptions import UserError


class FfCollection(models.Model):
    _inherit = 'ff.collection'

    handed_to = fields.Selection([
        ('company', 'The company'),
        ('distributor', 'The distributor'),
    ], string='Goes to', default='company', required=True, index=True, tracking=True,
        help='Money collected from a distributor goes to the company. Money collected from an '
             "outlet goes to that outlet's distributor, and is not owed to the office.")
    distributor_id = fields.Many2one('res.partner', string='Distributor', index=True,
                                     domain=[('ff_is_distributor', '=', True)])
    outlet_payment_id = fields.Many2one('ff.outlet.payment', string='Outlet Payment', readonly=True,
                                        copy=False, ondelete='set null')
    state = fields.Selection(selection_add=[('handed', 'Given to distributor')],
                             ondelete={'handed': 'set default'})

    @api.model
    def ff_create_from_app(self, employee, data):
        uuid = data.get('uuid') or False
        fresh = not (uuid and self.sudo().search_count([('client_uuid', '=', uuid)]))
        collection = super().ff_create_from_app(employee, data)
        if not fresh:
            return collection

        partner = collection.partner_id.sudo()
        goes_to = data.get('handed_to')
        if goes_to not in ('company', 'distributor'):
            # Left unsaid, it follows who paid: a distributor pays the company,
            # an outlet pays its distributor.
            goes_to = 'company' if partner.ff_is_distributor else 'distributor'

        if goes_to == 'distributor':
            distributor = self.env['res.partner'].sudo().browse(
                int(data.get('distributor_id') or 0)).exists() or partner.ff_distributor_id
            if not distributor:
                raise UserError(self.env._(
                    '%s has no distributor. Choose who the money is being given to.', partner.display_name))
            collection.sudo().write({
                'handed_to': 'distributor',
                'distributor_id': distributor.id,
                # Not the office's to wait for: it never joins the deposit.
                'state': 'handed',
            })
            payment = self.env['ff.outlet.payment'].ff_record(collection, data.get('allocations'))
            collection.sudo().outlet_payment_id = payment.id
        else:
            collection.sudo().write({'handed_to': 'company'})
            ids = [int(i) for i in (data.get('invoice_ids') or []) if str(i).isdigit()]
            if ids and 'move_ids' in self._fields:
                family = partner.commercial_partner_id
                moves = self.env['account.move'].sudo().search([
                    ('id', 'in', ids), ('move_type', '=', 'out_invoice'),
                    ('partner_id', 'child_of', family.id)])
                collection.sudo().write({'move_ids': [(6, 0, moves.ids)]})
        return collection
