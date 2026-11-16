from odoo import fields, models


class FfDemandNotes(models.Model):
    """The debit and credit notes raised with a demand (a sample collection or free goods): shown on the demand."""
    _inherit = 'ff.demand'

    ff_note_ids = fields.One2many('ff.distributor.note', 'demand_id', string='Debit / Credit Notes', readonly=True)

    def ff_app_payload(self, with_lines=True):
        # A demand with free goods that has gone to a distributor always has its debit note: one sent before notes were
        # automatic gets it the first time it is opened.
        for demand in self.sudo().filtered(lambda d: d.request_id and d.distributor_id
                                           and d.state not in ('draft', 'cancelled', 'rejected')):
            try:
                with self.env.cr.savepoint():
                    demand._ff_foc_note()
            except Exception:  # noqa: BLE001 - the screen must open even when the note cannot be raised
                pass
        payload = super().ff_app_payload(with_lines=with_lines)
        kinds = {'credit': 'Credit Note', 'debit': 'Debit Note'}
        waiting = {'pending': 'Waiting for manager approval', 'approved': 'Approved by the manager - accounts to post',
                   'rejected': 'Rejected'}

        def status(note):
            move = note.move_id
            if move and move.state == 'posted':
                return 'Posted'
            if move and move.state == 'cancel':
                return 'Cancelled'
            if move and move.ff_approval_state:
                return waiting.get(move.ff_approval_state, 'Draft')
            return {'pending': 'Waiting for approval', 'approved': 'Approved', 'rejected': 'Rejected'}.get(note.state, '')

        payload['notes'] = [{
            'id': note.id,
            # The accounting number once posted, else the note's own.
            'name': note.move_id.name if note.move_id and note.move_id.state == 'posted' else note.name,
            'kind': note.kind, 'kind_label': kinds.get(note.kind, note.kind),
            'amount': note.amount, 'state': note.state, 'status': status(note),
            'source': dict(note._fields['source'].selection).get(note.source, ''),
        } for note in self.sudo().ff_note_ids]
        return payload
