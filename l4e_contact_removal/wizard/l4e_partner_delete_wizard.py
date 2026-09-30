from odoo import api, fields, models, _
from odoo.exceptions import UserError


class L4ePartnerDeleteWizard(models.TransientModel):
    _name = 'l4e.partner.delete.wizard'
    _description = 'Global Contact Removal Wizard'

    partner_id = fields.Many2one(
        'res.partner',
        string='Contact to Remove',
        required=True,
        readonly=True,
    )
    partner_name = fields.Char(
        related='partner_id.display_name',
        string='Contact Name',
        readonly=True,
    )
    related_records_summary = fields.Html(
        string='Related Records Breakdown',
        readonly=True,
    )
    total_records_count = fields.Integer(
        string='Total Related Records',
        readonly=True,
    )
    confirm_checkbox = fields.Boolean(
        string='I understand that this action is permanent, irreversible, and will delete all related records across the database.',
        default=False,
    )

    @api.model
    def default_get(self, fields_list):
        res = super().default_get(fields_list)
        active_id = self.env.context.get('active_id') or (
            self.env.context.get('active_ids') and self.env.context.get('active_ids')[0]
        )
        if not active_id and self.env.context.get('default_partner_id'):
            active_id = self.env.context.get('default_partner_id')

        if active_id:
            partner = self.env['res.partner'].browse(active_id).exists()
            if partner:
                self._check_safety(partner)
                res['partner_id'] = partner.id
                summary_html, total_count = self._survey_related_records(partner)
                res['related_records_summary'] = summary_html
                res['total_records_count'] = total_count
        return res

    def _check_safety(self, partner):
        """Block accidental deletion of critical system entities."""
        # 1. Superuser
        if partner.id == 1:
            raise UserError(_("Security Protection: The system superuser partner (ID 1) cannot be deleted."))

        # 2. Company Partners
        company_partners = self.env['res.company'].sudo().search([]).mapped('partner_id')
        if partner in company_partners:
            raise UserError(_("Security Protection: '%s' is registered as a Company partner and cannot be deleted.", partner.name))

        # 3. Current logged in user
        if partner == self.env.user.partner_id:
            raise UserError(_("Security Protection: You cannot delete your own user contact!"))

        # 4. Internal Users
        internal_users = self.env['res.users'].sudo().search([
            ('partner_id', '=', partner.id),
            ('share', '=', False)
        ])
        if internal_users:
            raise UserError(_(
                "Security Protection: '%s' is linked to internal system user '%s' and cannot be deleted with this tool.",
                partner.name, internal_users[0].login
            ))

    def _survey_related_records(self, partner):
        """Scan database models and count related records for preview in wizard."""
        all_partners = self.env['res.partner'].sudo().with_context(active_test=False).search([('id', 'child_of', partner.id)])
        partner_ids = all_partners.ids
        counts = {}
        total = 0

        model_checks = [
            ('Sale Orders', 'sale.order', ['|', '|', ('partner_id', 'in', partner_ids), ('partner_invoice_id', 'in', partner_ids), ('partner_shipping_id', 'in', partner_ids)]),
            ('Purchase Orders', 'purchase.order', [('partner_id', 'in', partner_ids)]),
            ('Invoices & Bills', 'account.move', ['|', ('partner_id', 'in', partner_ids), ('commercial_partner_id', 'in', partner_ids)]),
            ('Payments', 'account.payment', [('partner_id', 'in', partner_ids)]),
            ('Stock Deliveries / Receipts', 'stock.picking', [('partner_id', 'in', partner_ids)]),
            ('CRM Leads / Opportunities', 'crm.lead', [('partner_id', 'in', partner_ids)]),
            ('Field Force Visits', 'ff.visit', [('partner_id', 'in', partner_ids)]),
            ('Field Force Demands', 'ff.demand', ['|', ('partner_id', 'in', partner_ids), ('distributor_id', 'in', partner_ids)]),
            ('Field Force Collections', 'ff.collection', [('partner_id', 'in', partner_ids)]),
            ('Field Force Returns', 'ff.return', [('partner_id', 'in', partner_ids)]),
            ('Field Force Tasks', 'ff.task', [('partner_id', 'in', partner_ids)]),
            ('Field Force Form Responses', 'ff.form.response', [('partner_id', 'in', partner_ids)]),
            ('Distributor MRP Lines', 'distributor.mrp.line', [('partner_id', 'in', partner_ids)]),
            ('Activities', 'mail.activity', [('res_model', '=', 'res.partner'), ('res_id', 'in', partner_ids)]),
            ('Chatter Messages & Notes', 'mail.message', [('model', '=', 'res.partner'), ('res_id', 'in', partner_ids)]),
            ('Followers', 'mail.followers', ['|', ('partner_id', 'in', partner_ids), '&', ('res_model', '=', 'res.partner'), ('res_id', 'in', partner_ids)]),
            ('Attachments', 'ir.attachment', [('res_model', '=', 'res.partner'), ('res_id', 'in', partner_ids)]),
        ]

        if len(partner_ids) > 1:
            child_count = len(partner_ids) - 1
            counts['Sub-contacts / Delivery Addresses'] = child_count
            total += child_count

        for label, model_name, domain in model_checks:
            if model_name in self.env:
                try:
                    cnt = self.env[model_name].sudo().with_context(active_test=False).search_count(domain)
                    if cnt > 0:
                        counts[label] = cnt
                        total += cnt
                except Exception:
                    pass

        # Build clean HTML summary table
        if not counts:
            html = """
            <div class="alert alert-info py-2" role="status">
                <i class="fa fa-info-circle me-1"/> <strong>No active transactions or related records found.</strong>
                Only the contact profile will be deleted.
            </div>
            """
        else:
            table_rows = "".join([
                f"""<tr>
                    <td class="py-1 ps-2">{label}</td>
                    <td class="py-1 pe-2 text-end fw-bold">
                        <span class="badge bg-danger text-white rounded-pill px-2">{count}</span>
                    </td>
                </tr>"""
                for label, count in counts.items()
            ])
            html = f"""
            <div class="alert alert-danger py-2 mb-2" role="alert">
                <i class="fa fa-exclamation-triangle me-1"/> <strong>Found {total} related record(s) in the database.</strong>
                All listed records below and this contact will be permanently destroyed.
            </div>
            <div class="border rounded" style="max-height: 220px; overflow-y: auto;">
                <table class="table table-sm table-striped mb-0">
                    <thead class="table-light sticky-top">
                        <tr>
                            <th class="ps-2">Related Document / Record Type</th>
                            <th class="text-end pe-2">Count</th>
                        </tr>
                    </thead>
                    <tbody>
                        {table_rows}
                    </tbody>
                </table>
            </div>
            """

        return html, total

    def action_confirm_delete(self):
        """Execute the global deletion after confirmation."""
        self.ensure_one()
        if not self.confirm_checkbox:
            raise UserError(_("You must check the confirmation checkbox before you can permanently delete this contact."))

        partner = self.partner_id
        if not partner.exists():
            raise UserError(_("Contact not found or already deleted."))

        self._check_safety(partner)
        partner_name = partner.display_name or partner.name

        # Execute the full cascade purge
        partner.action_purge_globally()

        # Display success toast and redirect to contacts view
        return {
            'type': 'ir.actions.client',
            'tag': 'display_notification',
            'params': {
                'title': _('Contact Deleted'),
                'message': _("Contact '%s' and all related records have been permanently deleted.", partner_name),
                'type': 'success',
                'sticky': False,
                'next': {
                    'type': 'ir.actions.act_window',
                    'res_model': 'res.partner',
                    'view_mode': 'kanban,list,form',
                    'views': [[False, 'kanban'], [False, 'list'], [False, 'form']],
                    'target': 'main',
                }
            }
        }
