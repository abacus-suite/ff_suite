"""Why a request was rejected, kept for the Approval Report whatever kind of request it was."""
from odoo import api, fields, models


class FfRejectReason(models.Model):
    _name = 'ff.reject.reason'
    _description = 'Rejection Reason'
    _order = 'id desc'

    res_model = fields.Char(required=True, index=True)
    res_id = fields.Integer(required=True, index=True)
    reason = fields.Text(required=True)
    decided_by_id = fields.Many2one('hr.employee', string='Rejected by', ondelete='set null')

    @api.model
    def ff_save(self, record, reason, employee=None):
        """Remember the reason for ``record``; a later rejection of the same record replaces it."""
        reason = (reason or '').strip()
        if not reason or not record:
            return False
        found = self.sudo().search([('res_model', '=', record._name), ('res_id', '=', record.id)], limit=1)
        vals = {'reason': reason, 'decided_by_id': employee.id if employee else False}
        if found:
            found.write(vals)
            return found
        return self.sudo().create(dict(vals, res_model=record._name, res_id=record.id))

    @api.model
    def ff_reasons(self, model, ids):
        """{record id: reason} for the records of ``model`` given."""
        rows = self.sudo().search([('res_model', '=', model), ('res_id', 'in', list(ids))])
        return {row.res_id: row.reason for row in rows}
