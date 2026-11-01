from . import models
from . import controllers

# Flavour MRP per price category, as in the client's deck (page 4). Matched on the product code.
_PRICES = {
    '149': {'AM': 149, 'BM': 149, 'BD': 149, 'CG': 169, 'OR': 149, 'LR': 149, 'MS': 199, 'PB': 149, 'GG': 149},
    '179': {'AM': 179, 'BM': 179, 'BD': 179, 'CG': 179, 'OR': 179, 'LR': 179, 'MS': 199, 'PB': 179, 'GG': 179},
}


def post_init(env):
    """Create the 149 and 179 price categories and fill the MRP of every flavour whose code matches."""
    Category = env['ff.event.price.category'].sudo()
    Line = env['ff.event.price.line'].sudo()
    templates = env['product.template'].sudo().search([('default_code', 'in', list(_PRICES['149']))])
    for name, prices in _PRICES.items():
        category = Category.search([('name', '=', name)], limit=1) or Category.create({'name': name})
        for template in templates:
            mrp = prices.get(template.default_code)
            if mrp and not Line.search_count([('category_id', '=', category.id), ('product_id', '=', template.id)]):
                Line.create({'category_id': category.id, 'product_id': template.id, 'mrp': mrp})
        # Every other flavour starts at the product's own MRP (ff_mrp); the office adjusts what differs.
        category.action_load_flavours()
