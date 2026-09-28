from odoo.exceptions import AccessError, UserError, ValidationError
from odoo.tests import TransactionCase, tagged


@tagged('post_install', '-at_install', 'ff')
class TestExpenses(TransactionCase):

    @classmethod
    def setUpClass(cls):
        super().setUpClass()
        cls.sales = cls.env['hr.department'].create({'name': 'Field Sales'})
        cls.manager = cls.env['hr.employee'].create({
            'name': 'Expense Manager', 'ff_access_scope': 'hierarchy', 'department_id': cls.sales.id,
        })
        cls.employee = cls.env['hr.employee'].create({
            'name': 'Expense Officer', 'tz': 'UTC', 'department_id': cls.sales.id, 'parent_id': cls.manager.id,
        })
        cls.food = cls.env.ref('ff_expenses.expense_category_food')
        cls.entertainment = cls.env.ref('ff_expenses.expense_category_client')
        cls.Claim = cls.env['ff.expense.claim']

    def test_claim_from_app_needs_receipt(self):
        with self.assertRaises(UserError):
            self.Claim.ff_create_from_app(self.employee, {'category_id': self.food.id, 'amount': 250})
        claim = self.Claim.ff_create_from_app(self.employee, {
            'category_id': self.food.id, 'amount': 250, 'note': 'Lunch', 'uuid': 'exp-1',
            'receipts': ['iVBORw0KGgo='],
        })
        self.assertEqual(claim.state, 'submitted')
        self.assertEqual(claim.receipt_count, 1)
        self.assertEqual(self.Claim.ff_create_from_app(self.employee, {'uuid': 'exp-1'}), claim)

    def test_category_rules(self):
        with self.assertRaises(UserError):  # contact required for entertainment
            self.Claim.ff_create_from_app(self.employee, {
                'category_id': self.entertainment.id, 'amount': 500, 'receipts': ['iVBORw0KGgo='],
            })
        self.food.max_amount = 100
        with self.assertRaises(ValidationError):
            self.Claim.ff_create_from_app(self.employee, {
                'category_id': self.food.id, 'amount': 250, 'receipts': ['iVBORw0KGgo='],
            })
        other_department = self.env['hr.department'].create({'name': 'Warehouse'})
        self.food.department_ids = other_department
        with self.assertRaises(UserError):
            self.Claim.ff_create_from_app(self.employee, {
                'category_id': self.food.id, 'amount': 50, 'receipts': ['iVBORw0KGgo='],
            })

    def test_manager_decides_within_scope(self):
        claim = self.Claim.ff_create_from_app(self.employee, {
            'category_id': self.food.id, 'amount': 120, 'receipts': ['iVBORw0KGgo='],
        })
        outsider = self.env['hr.employee'].create({'name': 'Other Manager', 'ff_access_scope': 'hierarchy'})
        with self.assertRaises(AccessError):
            claim._ff_decide_as(outsider, True)
        claim._ff_decide_as(self.manager, True)
        self.assertEqual(claim.state, 'approved')
        with self.assertRaises(UserError):  # already decided
            claim._ff_decide_as(self.manager, False)

    def test_a_number_is_given_when_the_claim_is_approved(self):
        claim = self.Claim.ff_create_from_app(self.employee, {
            'category_id': self.category.id, 'amount': 120.0, 'note': 'Bus fare'})
        self.assertFalse(claim.ff_reference, 'an unapproved claim is not a numbered document')
        claim.action_submit()
        claim._ff_set_decision(True, self.env.uid)
        self.assertTrue(claim.ff_reference)
        self.assertTrue(claim.ff_reference.startswith('EXP/'))

    def test_a_rejected_claim_never_takes_a_number(self):
        claim = self.Claim.ff_create_from_app(self.employee, {
            'category_id': self.category.id, 'amount': 90.0})
        claim.action_submit()
        claim._ff_set_decision(False, self.env.uid)
        self.assertFalse(claim.ff_reference)

    def test_the_office_decides_the_format(self):
        sequence = self.env['ir.sequence'].sudo().search([('code', '=', 'ff.expense.claim')], limit=1)
        sequence.write({'prefix': 'CLAIM-', 'padding': 3})
        claim = self.Claim.ff_create_from_app(self.employee, {
            'category_id': self.category.id, 'amount': 60.0})
        claim.action_submit()
        claim._ff_set_decision(True, self.env.uid)
        self.assertTrue(claim.ff_reference.startswith('CLAIM-'))
        self.assertEqual(len(claim.ff_reference.split('CLAIM-')[1]), 3)
