from odoo.exceptions import AccessError
from odoo.tests import TransactionCase, tagged


@tagged('post_install', '-at_install', 'ff')
class TestApprovalChain(TransactionCase):
    """First approver, then second, and everybody told."""

    @classmethod
    def setUpClass(cls):
        super().setUpClass()
        cls.first_user = cls.env['res.users'].create({
            'name': 'Area Manager', 'login': 'ff_first_approver'})
        cls.second_user = cls.env['res.users'].create({
            'name': 'Branch Head', 'login': 'ff_second_approver'})
        cls.first = cls.env['hr.employee'].create({
            'name': 'Area Manager', 'user_id': cls.first_user.id, 'ff_access_scope': 'hierarchy'})
        cls.officer = cls.env['hr.employee'].create({
            'name': 'Claiming Officer', 'parent_id': cls.first.id})
        cls.category = cls.env['ff.expense.category'].create({'name': 'Travel', 'requires_receipt': False})
        cls.flow = cls.env['ff.approval.flow'].create({
            'name': 'Two signatures',
            'document': 'ff.expense.claim',
            'step_ids': [
                (0, 0, {'sequence': 10, 'name': 'Reporting manager', 'approver_kind': 'manager'}),
                (0, 0, {'sequence': 20, 'name': 'Branch head', 'approver_kind': 'user',
                        'user_id': cls.second_user.id}),
            ],
        })
        cls.Claim = cls.env['ff.expense.claim']

    def _claim(self, amount=500.0):
        claim = self.Claim.ff_create_from_app(self.officer, {
            'category_id': self.category.id, 'amount': amount, 'note': 'Bus and lunch'})
        claim.action_submit()
        return claim

    def test_submitting_builds_the_chain_and_asks_the_first_person(self):
        claim = self._claim()
        steps = claim.approval_line_ids.sorted('sequence')
        self.assertEqual(len(steps), 2)
        self.assertEqual(steps[0].user_id, self.first_user)
        self.assertEqual(steps[1].user_id, self.second_user)
        self.assertEqual(claim.approver_user_id, self.first_user, 'it waits for the first approver')

    def test_the_first_approval_does_not_settle_it(self):
        claim = self._claim()
        claim._ff_decide_step(self.first_user, True)
        self.assertEqual(claim.state, 'submitted', 'one signature of two is not a decision')
        self.assertEqual(claim.approver_user_id, self.second_user)

    def test_the_last_approval_settles_it(self):
        claim = self._claim()
        claim._ff_decide_step(self.first_user, True)
        claim._ff_decide_step(self.second_user, True)
        self.assertEqual(claim.state, 'approved')
        self.assertTrue(claim.ff_reference, 'and it takes its number')

    def test_a_rejection_ends_it_wherever_it_stands(self):
        claim = self._claim()
        claim._ff_decide_step(self.first_user, False, 'Not a business trip')
        self.assertEqual(claim.state, 'rejected')
        self.assertFalse(claim.approver_user_id)
        self.assertEqual(claim.approval_line_ids.filtered(lambda l: l.state == 'skipped').name,
                         'Branch head')

    def test_somebody_out_of_turn_cannot_sign(self):
        claim = self._claim()
        with self.assertRaises(AccessError):
            claim._ff_decide_step(self.second_user, True)

    def test_the_approver_and_the_claimant_are_told(self):
        Notification = self.env['ff.notification']
        claim = self._claim()
        waiting = Notification.sudo().search([
            ('employee_id', '=', self.first.id), ('kind', '=', 'approval')])
        self.assertTrue(waiting, 'the first approver hears about it')

        claim._ff_decide_step(self.first_user, True)
        claim._ff_decide_step(self.second_user, True)
        told = Notification.sudo().search([
            ('employee_id', '=', self.officer.id), ('kind', '=', 'decision')])
        self.assertTrue(told, 'the person who claimed hears the outcome')
        self.assertIn('approved', told[0].body)

    def test_without_a_flow_one_signature_is_enough(self):
        self.flow.active = False
        claim = self._claim()
        self.assertFalse(claim.approval_line_ids)
        claim._ff_set_decision(True, self.first_user.id)
        self.assertEqual(claim.state, 'approved')

    def test_a_flow_can_apply_only_above_an_amount(self):
        self.flow.min_amount = 1000.0
        small = self._claim(200.0)
        self.assertFalse(small.approval_line_ids, 'a small claim keeps the simple path')
        big = self._claim(5000.0)
        self.assertEqual(len(big.approval_line_ids), 2)

    def test_unread_notifications_can_be_cleared(self):
        self._claim()
        rows = self.env['ff.notification'].ff_for(self.first, unread_only=True)
        self.assertTrue(rows)
        rows.ff_mark_read()
        self.assertFalse(self.env['ff.notification'].ff_for(self.first, unread_only=True))
