import logging
from odoo import api, fields, models, _
from odoo.exceptions import UserError

_logger = logging.getLogger(__name__)


class ResPartner(models.Model):
    _inherit = 'res.partner'

    def action_open_global_delete_wizard(self):
        """Open the Global Delete confirmation wizard from the Action menu.

        Creates the wizard record server-side and passes res_id so Odoo opens
        an existing record (not a NewId draft). Uses target='current' (full-page)
        to avoid Odoo's background form webRead refresh that causes MissingRecord
        on portal-linked partners.
        """
        self.ensure_one()
        wizard = self.env['l4e.partner.delete.wizard'].with_context(
            default_partner_id=self.id,
        ).create({})
        return {
            'name': _('Global Delete Contact'),
            'type': 'ir.actions.act_window',
            'res_model': 'l4e.partner.delete.wizard',
            'res_id': wizard.id,
            'view_mode': 'form',
            'target': 'current',
        }

    def _get_protected_partners(self):
        """Identify critical partner records that must never be deleted."""
        protected = set()
        # 1. System root partner (ID 1)
        protected.add(1)

        # 2. Company partners
        try:
            company_partner_ids = self.env['res.company'].sudo().search([]).mapped('partner_id').ids
            protected.update(company_partner_ids)
        except Exception:
            pass

        # 3. Current logged-in user partner
        if self.env.user.partner_id:
            protected.add(self.env.user.partner_id.id)

        # 4. Internal system users
        try:
            internal_user_partners = self.env['res.users'].sudo().search([
                ('share', '=', False)
            ]).mapped('partner_id').ids
            protected.update(internal_user_partners)
        except Exception:
            pass

        return protected

    def action_purge_globally(self):
        """Permanently delete this contact and all its related records across the entire database."""
        self.ensure_one()

        protected_ids = self._get_protected_partners()
        if self.id in protected_ids:
            if self.id == 1:
                raise UserError(_("Security Protection: The system superuser partner cannot be deleted."))
            if self.id == self.env.user.partner_id.id:
                raise UserError(_("Security Protection: You cannot delete your own user contact."))
            raise UserError(_("Security Protection: '%s' is a protected system/company/internal user partner and cannot be deleted.", self.display_name))

        Partner = self.env['res.partner'].sudo().with_context(active_test=False)
        all_partners = Partner.search([('id', 'child_of', self.id)])
        
        # Verify no protected partners are among child contacts
        conflict_protected = set(all_partners.ids) & protected_ids
        if conflict_protected:
            raise UserError(_(
                "Security Protection: This contact contains linked sub-contacts that are protected internal/company records (IDs: %s).",
                list(conflict_protected)
            ))

        partner_ids = tuple(all_partners.ids)
        if not partner_ids:
            return True

        cr = self.env.cr

        # Fast in-memory catalog cache: 1 instant query instead of 50+ roundtrips
        cr.execute("""
            SELECT c.relname, a.attname
            FROM pg_attribute a
            JOIN pg_class c ON a.attrelid = c.oid
            JOIN pg_namespace n ON c.relnamespace = n.oid
            WHERE n.nspname = 'public' AND c.relkind = 'r' AND a.attnum > 0 AND NOT a.attisdropped
        """)
        col_rows = cr.fetchall()
        existing_columns = {(r[0], r[1]) for r in col_rows}
        existing_tables = {r[0] for r in col_rows}

        def _table_exists(table_name):
            return table_name in existing_tables

        def _column_exists(table_name, column_name):
            return (table_name, column_name) in existing_columns

        saved_partner_name = self.display_name or self.name or f"Partner #{self.id}"
        _logger.info("L4E Contact Removal: Starting global purge for partner %s (IDs: %s)", saved_partner_name, partner_ids)

        # ─────────────────────────────────────────────────────────────────
        # Phase 0: Portal Users
        # If this partner has portal/share user accounts, delete them first so they don't block
        # ─────────────────────────────────────────────────────────────────
        if _table_exists('res_users'):
            portal_users = self.env['res.users'].sudo().search([
                ('partner_id', 'in', partner_ids),
                ('share', '=', True)
            ])
            if portal_users:
                _logger.info("L4E Contact Removal: Removing portal users for partner: %s", portal_users.ids)
                portal_users.unlink()

        # ─────────────────────────────────────────────────────────────────
        # Phase 1: Transactions & Operational Documents
        # ─────────────────────────────────────────────────────────────────

        # Invoicing / Accounting
        if _table_exists('account_payment'):
            cr.execute("DELETE FROM account_payment WHERE partner_id IN %s", (partner_ids,))

        if _table_exists('account_move'):
            # Moves where this contact is the partner or commercial partner
            cr.execute("""
                SELECT id FROM account_move 
                WHERE partner_id IN %s OR commercial_partner_id IN %s
            """, (partner_ids, partner_ids))
            move_ids = [r[0] for r in cr.fetchall()]
            if move_ids:
                move_ids_tuple = tuple(move_ids)
                if _table_exists('account_move_line'):
                    cr.execute("DELETE FROM account_move_line WHERE move_id IN %s", (move_ids_tuple,))
                cr.execute("DELETE FROM account_move WHERE id IN %s", (move_ids_tuple,))

        # For remaining move lines belonging to third-party moves that reference this partner:
        if _table_exists('account_move_line'):
            cr.execute("UPDATE account_move_line SET partner_id = NULL WHERE partner_id IN %s", (partner_ids,))

        # Sales Orders
        if _table_exists('sale_order'):
            query = """
                SELECT id FROM sale_order 
                WHERE partner_id IN %s OR partner_invoice_id IN %s OR partner_shipping_id IN %s
            """
            params = [partner_ids, partner_ids, partner_ids]
            if _column_exists('sale_order', 'outlet_id'):
                query += " OR outlet_id IN %s"
                params.append(partner_ids)

            cr.execute(query, tuple(params))
            sale_ids = [r[0] for r in cr.fetchall()]
            if sale_ids:
                sale_ids_tuple = tuple(sale_ids)
                if _table_exists('sale_order_line'):
                    cr.execute("DELETE FROM sale_order_line WHERE order_id IN %s", (sale_ids_tuple,))
                cr.execute("DELETE FROM sale_order WHERE id IN %s", (sale_ids_tuple,))

        # Purchase Orders
        if _table_exists('purchase_order'):
            cr.execute("SELECT id FROM purchase_order WHERE partner_id IN %s", (partner_ids,))
            po_ids = [r[0] for r in cr.fetchall()]
            if po_ids:
                po_ids_tuple = tuple(po_ids)
                if _table_exists('purchase_order_line'):
                    cr.execute("DELETE FROM purchase_order_line WHERE order_id IN %s", (po_ids_tuple,))
                cr.execute("DELETE FROM purchase_order WHERE id IN %s", (po_ids_tuple,))

        # Stock Pickings
        if _table_exists('stock_picking'):
            cr.execute("SELECT id FROM stock_picking WHERE partner_id IN %s", (partner_ids,))
            picking_ids = [r[0] for r in cr.fetchall()]
            if picking_ids:
                picking_ids_tuple = tuple(picking_ids)
                if _table_exists('stock_move_line'):
                    cr.execute("DELETE FROM stock_move_line WHERE picking_id IN %s", (picking_ids_tuple,))
                if _table_exists('stock_move'):
                    cr.execute("DELETE FROM stock_move WHERE picking_id IN %s", (picking_ids_tuple,))
                cr.execute("DELETE FROM stock_picking WHERE id IN %s", (picking_ids_tuple,))

        # CRM Leads
        if _table_exists('crm_lead'):
            cr.execute("DELETE FROM crm_lead WHERE partner_id IN %s", (partner_ids,))

        # Calendar Events
        if _table_exists('calendar_event'):
            if _table_exists('calendar_event_res_partner_rel'):
                cr.execute("DELETE FROM calendar_event_res_partner_rel WHERE res_partner_id IN %s", (partner_ids,))
            if _column_exists('calendar_event', 'partner_id'):
                cr.execute("DELETE FROM calendar_event WHERE partner_id IN %s", (partner_ids,))

        # ─────────────────────────────────────────────────────────────────
        # Phase 2: Field Force Suite (ff_*)
        # ─────────────────────────────────────────────────────────────────

        # Visits and related steps/counts
        if _table_exists('ff_visit') and _column_exists('ff_visit', 'partner_id'):
            cr.execute("SELECT id FROM ff_visit WHERE partner_id IN %s", (partner_ids,))
            visit_ids = [r[0] for r in cr.fetchall()]
            if visit_ids:
                visit_ids_tuple = tuple(visit_ids)
                if _table_exists('ff_visit_step_record') and _column_exists('ff_visit_step_record', 'visit_id'):
                    cr.execute("DELETE FROM ff_visit_step_record WHERE visit_id IN %s", (visit_ids_tuple,))
                if _table_exists('ff_stock_count') and _column_exists('ff_stock_count', 'visit_id'):
                    cr.execute("DELETE FROM ff_stock_count WHERE visit_id IN %s", (visit_ids_tuple,))
            if _table_exists('ff_stock_count') and _column_exists('ff_stock_count', 'partner_id'):
                cr.execute("DELETE FROM ff_stock_count WHERE partner_id IN %s", (partner_ids,))
            cr.execute("DELETE FROM ff_visit WHERE partner_id IN %s", (partner_ids,))

        # Demands
        if _table_exists('ff_demand') and _column_exists('ff_demand', 'partner_id'):
            query = "SELECT id FROM ff_demand WHERE partner_id IN %s"
            params = [partner_ids]
            if _column_exists('ff_demand', 'distributor_id'):
                query += " OR distributor_id IN %s"
                params.append(partner_ids)
            cr.execute(query, tuple(params))
            demand_ids = [r[0] for r in cr.fetchall()]
            if demand_ids:
                demand_ids_tuple = tuple(demand_ids)
                if _table_exists('ff_demand_line') and _column_exists('ff_demand_line', 'demand_id'):
                    cr.execute("DELETE FROM ff_demand_line WHERE demand_id IN %s", (demand_ids_tuple,))
                cr.execute("DELETE FROM ff_demand WHERE id IN %s", (demand_ids_tuple,))

        # Collections
        if _table_exists('ff_collection') and _column_exists('ff_collection', 'partner_id'):
            cr.execute("DELETE FROM ff_collection WHERE partner_id IN %s", (partner_ids,))

        # Returns
        if _table_exists('ff_return') and _column_exists('ff_return', 'partner_id'):
            cr.execute("SELECT id FROM ff_return WHERE partner_id IN %s", (partner_ids,))
            return_ids = [r[0] for r in cr.fetchall()]
            if return_ids:
                return_ids_tuple = tuple(return_ids)
                if _table_exists('ff_return_line') and _column_exists('ff_return_line', 'return_id'):
                    cr.execute("DELETE FROM ff_return_line WHERE return_id IN %s", (return_ids_tuple,))
                cr.execute("DELETE FROM ff_return WHERE id IN %s", (return_ids_tuple,))

        # Tasks
        if _table_exists('ff_task') and _column_exists('ff_task', 'partner_id'):
            cr.execute("DELETE FROM ff_task WHERE partner_id IN %s", (partner_ids,))

        # Form Responses
        if _table_exists('ff_form_response') and _column_exists('ff_form_response', 'partner_id'):
            cr.execute("DELETE FROM ff_form_response WHERE partner_id IN %s", (partner_ids,))

        # Expense Claims
        if _table_exists('ff_expense_claim') and _column_exists('ff_expense_claim', 'partner_id'):
            cr.execute("UPDATE ff_expense_claim SET partner_id = NULL WHERE partner_id IN %s", (partner_ids,))

        # Distributor MRP Lines
        if _table_exists('distributor_mrp_line') and _column_exists('distributor_mrp_line', 'partner_id'):
            cr.execute("DELETE FROM distributor_mrp_line WHERE partner_id IN %s", (partner_ids,))

        # Beat references
        if _table_exists('ff_beat') and _column_exists('ff_beat', 'ff_distributor_id'):
            cr.execute("UPDATE ff_beat SET ff_distributor_id = NULL WHERE ff_distributor_id IN %s", (partner_ids,))

        # ─────────────────────────────────────────────────────────────────
        # Phase 3: Communication, Tracking & Metadata
        # ─────────────────────────────────────────────────────────────────

        if _table_exists('mail_activity') and _column_exists('mail_activity', 'res_id'):
            if _column_exists('mail_activity', 'res_model'):
                cr.execute("DELETE FROM mail_activity WHERE res_model = 'res.partner' AND res_id IN %s", (partner_ids,))
            else:
                cr.execute("DELETE FROM mail_activity WHERE res_id IN %s", (partner_ids,))

        if _table_exists('mail_message'):
            if _column_exists('mail_message', 'model') and _column_exists('mail_message', 'res_id'):
                cr.execute("DELETE FROM mail_message WHERE model = 'res.partner' AND res_id IN %s", (partner_ids,))
            if _table_exists('mail_message_res_partner_rel'):
                cr.execute("DELETE FROM mail_message_res_partner_rel WHERE res_partner_id IN %s", (partner_ids,))
            if _column_exists('mail_message', 'author_id'):
                cr.execute("UPDATE mail_message SET author_id = NULL WHERE author_id IN %s", (partner_ids,))

        if _table_exists('mail_followers'):
            if _column_exists('mail_followers', 'res_model') and _column_exists('mail_followers', 'res_id'):
                cr.execute("DELETE FROM mail_followers WHERE res_model = 'res.partner' AND res_id IN %s", (partner_ids,))
            if _column_exists('mail_followers', 'partner_id'):
                cr.execute("DELETE FROM mail_followers WHERE partner_id IN %s", (partner_ids,))

        if _table_exists('ir_attachment') and _column_exists('ir_attachment', 'res_model') and _column_exists('ir_attachment', 'res_id'):
            cr.execute("DELETE FROM ir_attachment WHERE res_model = 'res.partner' AND res_id IN %s", (partner_ids,))

        # ─────────────────────────────────────────────────────────────────
        # Phase 4: Self-referencing Partner Links
        # ─────────────────────────────────────────────────────────────────
        if _column_exists('res_partner', 'parent_id'):
            cr.execute("UPDATE res_partner SET parent_id = NULL WHERE parent_id IN %s", (partner_ids,))
        if _column_exists('res_partner', 'commercial_partner_id'):
            cr.execute("UPDATE res_partner SET commercial_partner_id = id WHERE commercial_partner_id IN %s", (partner_ids,))
        if _column_exists('res_partner', 'ff_distributor_id'):
            cr.execute("UPDATE res_partner SET ff_distributor_id = NULL WHERE ff_distributor_id IN %s", (partner_ids,))

        # ─────────────────────────────────────────────────────────────────
        # Phase 5: Fast Native PostgreSQL Catalog Foreign Key Sweeper
        # Queries pg_constraint directly in ~1ms (no slow information_schema)
        # ─────────────────────────────────────────────────────────────────
        cr.execute("""
            SELECT
                c_child.relname AS child_table,
                a_child.attname AS child_column,
                NOT a_child.attnotnull AS is_nullable
            FROM pg_constraint con
            JOIN pg_class c_child ON con.conrelid = c_child.oid
            JOIN pg_attribute a_child ON a_child.attrelid = con.conrelid AND a_child.attnum = con.conkey[1]
            JOIN pg_class c_parent ON con.confrelid = c_parent.oid
            JOIN pg_namespace n ON c_child.relnamespace = n.oid
            WHERE c_parent.relname = 'res_partner'
              AND con.contype = 'f'
              AND n.nspname = 'public'
              AND con.confdeltype IN ('a', 'r')
              AND c_child.relname NOT IN ('res_partner', 'res_company', 'res_users')
        """)
        blocking_fks = cr.fetchall()

        for table_name, column_name, is_nullable in blocking_fks:
            # Every operation (SELECT + DML) inside its own savepoint so that
            # any PostgreSQL error on any table is fully isolated and cannot
            # poison the outer transaction.
            sp_name = f"l4e_fk_{table_name}"
            try:
                cr.execute(f"SAVEPOINT {sp_name}")
                try:
                    cr.execute(f"SELECT 1 FROM {table_name} WHERE {column_name} IN %s LIMIT 1", (partner_ids,))
                    has_rows = cr.fetchone()
                    if has_rows:
                        if is_nullable:
                            cr.execute(f"UPDATE {table_name} SET {column_name} = NULL WHERE {column_name} IN %s", (partner_ids,))
                        else:
                            cr.execute(f"DELETE FROM {table_name} WHERE {column_name} IN %s", (partner_ids,))
                    cr.execute(f"RELEASE SAVEPOINT {sp_name}")
                except Exception as e:
                    cr.execute(f"ROLLBACK TO SAVEPOINT {sp_name}")
                    cr.execute(f"RELEASE SAVEPOINT {sp_name}")
                    _logger.warning("L4E Contact Removal: Skipped FK table %s col %s: %s", table_name, column_name, e)
            except Exception:
                pass

        # Clean many-to-many partner join tables
        cr.execute("""
            SELECT c.relname, a.attname
            FROM pg_attribute a
            JOIN pg_class c ON a.attrelid = c.oid
            JOIN pg_namespace n ON c.relnamespace = n.oid
            WHERE n.nspname = 'public'
              AND c.relkind = 'r'
              AND c.relname LIKE '%res_partner%'
              AND c.relname != 'res_partner'
              AND a.attname LIKE '%partner%id%'
              AND a.attnum > 0 AND NOT a.attisdropped
        """)
        m2m_rows = cr.fetchall()
        for m2m_table, m2m_col in m2m_rows:
            sp_name = f"l4e_m2m_{m2m_table}"
            try:
                cr.execute(f"SAVEPOINT {sp_name}")
                try:
                    cr.execute(f"SELECT 1 FROM {m2m_table} WHERE {m2m_col} IN %s LIMIT 1", (partner_ids,))
                    if cr.fetchone():
                        cr.execute(f"DELETE FROM {m2m_table} WHERE {m2m_col} IN %s", (partner_ids,))
                    cr.execute(f"RELEASE SAVEPOINT {sp_name}")
                except Exception:
                    cr.execute(f"ROLLBACK TO SAVEPOINT {sp_name}")
                    cr.execute(f"RELEASE SAVEPOINT {sp_name}")
            except Exception:
                pass

        # ─────────────────────────────────────────────────────────────────
        # Phase 6: Delete Target Partner Records
        # ─────────────────────────────────────────────────────────────────
        cr.execute("DELETE FROM res_partner WHERE id IN %s", (partner_ids,))

        # Invalidate the entire ORM cache so no stale references persist in memory
        self.env.invalidate_all()
        _logger.info("L4E Contact Removal: Successfully purged partner %s (IDs: %s)", saved_partner_name, partner_ids)
        return True

