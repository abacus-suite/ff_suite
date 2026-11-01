"""Which products the task screens list, decided by the product category.

The task screens list flavours to count and order, and marketing material to
check and supply. Neither list is written into the app: a category says what
its products are, so a new flavour or a new kind of signage is a product in the
right category and nothing more.
"""
from odoo import fields, models


class ProductCategory(models.Model):
    _inherit = 'product.category'

    ff_tracking_needed = fields.Boolean(
        string='Tracking Needed',
        help='Products in this category are counted, ordered and sampled flavour by flavour in the '
             'field tasks: closing stock, demand, credit notes and samples.')
    ff_marketing_material = fields.Boolean(
        string='Marketing Material',
        help='Products in this category are marketing material: the field records whether an outlet '
             'has them, how many it needs, and how many were supplied.')


class ProductProduct(models.Model):
    _inherit = 'product.product'

    def _ff_task_domain(self, flag):
        categories = self.env['product.category'].sudo().search([(flag, '=', True)])
        return [('sale_ok', '=', True), ('categ_id', 'child_of', categories.ids)] if categories else [('id', '=', 0)]

    def ff_flavours(self):
        """Everything counted flavour by flavour, in the order it is shown."""
        return self.sudo().search(self._ff_task_domain('ff_tracking_needed'), order='default_code, name')

    def ff_materials(self):
        """Every kind of marketing material."""
        return self.sudo().search(self._ff_task_domain('ff_marketing_material'), order='name')
