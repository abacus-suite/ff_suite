from odoo import fields, models


class FfTaskType(models.Model):
    """Events is listed with the other tasks, so its start distance is set in the same place."""
    _inherit = 'ff.task.type'

    code = fields.Selection(selection_add=[('events', 'Events')], ondelete={'events': 'cascade'})
