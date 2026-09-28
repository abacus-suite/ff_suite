"""The letterhead a field document is printed on.

A summary sent to a distributor is read as coming from the company, not from
Odoo, so the company keeps its own header and footer strip and every Field
Force report is printed between the two. They are images on purpose: whatever
the printer already uses - a designed banner, a GST line, a bank detail strip -
is uploaded as it is, with nothing to rebuild.
"""
from odoo import fields, models


class ResCompany(models.Model):
    _inherit = 'res.company'

    ff_report_header_image = fields.Image(
        string='Report Header', max_width=2400, max_height=600,
        help='Printed full width across the top of Field Force PDFs. A wide, short image '
             'works best - around 2400 x 400 pixels.')
    ff_report_footer_image = fields.Image(
        string='Report Footer', max_width=2400, max_height=600,
        help='Printed full width across the bottom of Field Force PDFs.')
