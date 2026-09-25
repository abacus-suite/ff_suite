from odoo import models, fields


class HrEmployee(models.Model):
    _inherit = 'hr.employee'

    # ── General Info ──────────────────────────────────────────────────────────
    l4e_employee_type = fields.Selection(
        selection=[
            ('employee', 'Employee'),
            ('contractor', 'Contractor'),
        ],
        string='Employee Type',
        default='employee',
    )
    l4e_employee_id = fields.Char(
        string='Employee ID',
    )
    l4e_blood_group = fields.Selection(
        selection=[
            ('A+', 'A+'), ('A-', 'A-'),
            ('B+', 'B+'), ('B-', 'B-'),
            ('O+', 'O+'), ('O-', 'O-'),
            ('AB+', 'AB+'), ('AB-', 'AB-'),
        ],
        string='Blood Group',
    )
    l4e_date_of_joining = fields.Date(
        string='Date of Joining',
    )
    l4e_date_of_joining_pvt = fields.Date(
        string='Date of Joining (Pvt Ltd)',
    )
    l4e_probation_period = fields.Char(
        string='Probation Period',
        help='e.g. 3 Months, 6 Months',
    )
    l4e_immediate_reporting_person = fields.Many2one(
        'hr.employee',
        string='Immediate Reporting Person',
    )
    l4e_father_name = fields.Char(
        string="Father's Name",
    )
    l4e_highest_qualification = fields.Char(
        string='Highest Qualification',
    )
    l4e_unolo_id = fields.Char(
        string='Unolo / E-Time ID',
    )
    l4e_aadhaar_number = fields.Char(
        string='Aadhaar Number',
    )
    l4e_company_vehicle = fields.Char(
        string='Company Vehicle',
        help='e.g. Own, Company Provided, 4 Rs per km',
    )
    l4e_reference_hiring = fields.Char(
        string='Reference / Mode of Hiring',
    )
    l4e_remarks = fields.Text(
        string='Remarks',
    )

    # ── Salary / Allowances ───────────────────────────────────────────────────
    l4e_gross_salary_joining = fields.Float(
        string='Gross Salary on Joining (Rs.)',
    )
    l4e_dearness_allowance = fields.Float(
        string='Dearness Allowance (Rs.)',
    )
    l4e_conveyance_allowance = fields.Float(
        string='Conveyance Allowance (Rs.)',
    )
    l4e_medical_allowance = fields.Float(
        string='Medical Allowance (Rs.)',
    )
    l4e_special_allowance = fields.Float(
        string='Special Allowance (Rs.)',
    )
    l4e_travel_allowance = fields.Char(
        string='Travel Allowance',
        help='e.g. 4 Rs per km / Fixed Amount',
    )
    l4e_other_allowance = fields.Float(
        string='Other / Variable Allowance (Rs.)',
    )
    l4e_incentive = fields.Char(
        string='Incentive',
        help='e.g. As per Incentive Policy',
    )
    l4e_total_monthly_salary = fields.Float(
        string='Total Monthly Salary (Rs.)',
    )

    # ── Salary Revision History (One2many) ────────────────────────────────────
    l4e_salary_revision_ids = fields.One2many(
        'l4e.salary.revision',
        'employee_id',
        string='Salary Revision History',
    )
