# -*- coding: utf-8 -*-
import logging

_logger = logging.getLogger(__name__)


def post_init_hook(env):
    """
    Ensure the 4 stock locations exist and are linked to the main stock location,
    and activate multi-locations feature in Stock settings.
    """
    _logger.info("Initializing l4e_product_location post_init_hook...")

    # 1. Enable multi-location group for internal users so location fields are visible
    group_multi_loc = env.ref('stock.group_stock_multi_locations', raise_if_not_found=False)
    group_user = env.ref('base.group_user', raise_if_not_found=False)
    if group_multi_loc and group_user and group_multi_loc not in group_user.implied_ids:
        group_user.sudo().write({'implied_ids': [(4, group_multi_loc.id)]})
        _logger.info("Enabled stock.group_stock_multi_locations on base.group_user")

    # 2. Determine parent stock location (default WH/Stock or fallback)
    warehouse = env['stock.warehouse'].search([('company_id', '=', env.company.id)], limit=1)
    parent_loc = warehouse.lot_stock_id if warehouse else env.ref('stock.stock_location_stock', raise_if_not_found=False)

    locations_data = [
        ('l4e_product_location.location_storage_godown', 'Storage (Godown)'),
        ('l4e_product_location.location_fermentation', 'Fermentation'),
        ('l4e_product_location.location_bottling', 'Bottling'),
        ('l4e_product_location.location_packing', 'Packing'),
    ]

    for xml_id, loc_name in locations_data:
        loc = env.ref(xml_id, raise_if_not_found=False)
        if not loc:
            # Check if location already exists by name
            loc = env['stock.location'].search([
                ('name', '=', loc_name),
                ('usage', '=', 'internal'),
            ], limit=1)
            if not loc:
                loc = env['stock.location'].create({
                    'name': loc_name,
                    'usage': 'internal',
                    'location_id': parent_loc.id if parent_loc else False,
                })
                _logger.info("Created location: %s", loc_name)

            # Bind to xmlid
            env['ir.model.data']._update_xmlids([{
                'xml_id': xml_id,
                'record': loc,
                'noupdate': True,
            }])
        else:
            if parent_loc and not loc.location_id:
                loc.sudo().write({'location_id': parent_loc.id})
                _logger.info("Linked location %s to parent %s", loc_name, parent_loc.display_name)

    # 3. Synchronize existing incoming receipts
    if hasattr(env['stock.picking'], '_fix_existing_incoming_destinations'):
        env['stock.picking']._fix_existing_incoming_destinations()
