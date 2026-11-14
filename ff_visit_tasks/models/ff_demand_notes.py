from odoo import fields, models


class FfDemandNotes(models.Model):
    """The debit and credit notes raised with a demand (a sample collection or free goods): shown on the demand."""
    _inherit = 'ff.demand'

    ff_note_ids = fields.One2many('ff.distributor.note', 'demand_id', string='Debit / Credit Notes', readonly=True)

    def ff_app_payload(self, with_lines=True):
        payload = super().ff_app_payload(with_lines=with_lines)
        kinds = {'credit': 'Credit Note', 'debit': 'Debit Note'}
        payload['notes'] = [{
            'id': note.id, 'name': note.name, 'kind': note.kind, 'kind_label': kinds.get(note.kind, note.kind),
            'amount': note.amount, 'state': note.state,
        } for note in self.sudo().ff_note_ids]
        return payload
