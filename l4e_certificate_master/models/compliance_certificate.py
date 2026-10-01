# -*- coding: utf-8 -*-
from datetime import timedelta
from odoo import models, fields, api, _
from odoo.exceptions import UserError, ValidationError

class ComplianceCertificate(models.Model):
    _name = 'compliance.certificate'
    _description = 'Compliance Certificate & License'
    _inherit = ['mail.thread', 'mail.activity.mixin']
    _order = 'expiry_date asc, id desc'

    name = fields.Char(
        string='Certificate / License Name',
        required=True,
        tracking=True,
        help='e.g., FSSAI Central Manufacturing License, Pollution Control Consent, Fire NOC'
    )
    certificate_no = fields.Char(
        string='License / Certificate No',
        required=True,
        tracking=True,
        help='Unique registration or license number'
    )
    certificate_type = fields.Selection([
        ('fssai', 'Food Safety (FSSAI)'),
        ('factory', 'Factory License'),
        ('pollution', 'Pollution Control (PCB)'),
        ('fire', 'Fire Safety NOC'),
        ('water', 'Water / Effluent Quality Test'),
        ('iso', 'ISO / Quality Certification'),
        ('boiler', 'Boiler / Machinery Fitness'),
        ('legal', 'Trade / Legal Metrology'),
        ('other', 'Other Statutory License')
    ], string='Certificate Type', required=True, default='fssai', tracking=True)

    issuing_authority = fields.Char(
        string='Issuing Authority / Agency',
        tracking=True,
        help='e.g., FSSAI, State Pollution Control Board, Municipal Corporation'
    )
    issue_date = fields.Date(
        string='Issue Date',
        required=True,
        default=fields.Date.context_today,
        tracking=True
    )
    expiry_date = fields.Date(
        string='Expiry Date',
        required=True,
        tracking=True
    )

    responsible_id = fields.Many2one(
        'res.users',
        string='Responsible Person',
        required=True,
        default=lambda self: self.env.user,
        tracking=True,
        help='User responsible for tracking and processing renewals'
    )
    notification_partner_ids = fields.Many2many(
        'res.partner',
        'compliance_cert_partner_rel',
        'certificate_id',
        'partner_id',
        string='Additional Stakeholders',
        help='Extra team members or external consultants who should receive expiry alerts'
    )

    days_to_expire = fields.Integer(
        string='Days Remaining',
        compute='_compute_days_to_expire',
        store=True,
        tracking=True,
        help='Number of days until certificate expiry (negative if already expired)'
    )

    state = fields.Selection([
        ('draft', 'Draft'),
        ('active', 'Active / Valid'),
        ('expiring_30', 'Expiring (30 Days)'),
        ('expiring_15', 'Urgent (15 Days)'),
        ('expiring_7', 'Critical (7 Days)'),
        ('expired', 'Expired'),
        ('renewed', 'Renewed / Replaced'),
        ('cancelled', 'Cancelled')
    ], string='Status', default='draft', tracking=True, compute='_compute_status_and_alerts', store=True, readonly=False)

    alert_stage = fields.Selection([
        ('none', 'No Alert Sent'),
        ('alert_30', '30-Day Alert Sent'),
        ('alert_15', '15-Day Alert Sent'),
        ('alert_7', '7-Day Alert Sent'),
        ('expired_alert', 'Expired Alert Sent')
    ], string='Last Alert Triggered', default='none', tracking=True, copy=False)

    certificate_file = fields.Binary(string='Certificate Document (PDF/Image)', attachment=True)
    file_name = fields.Char(string='File Name')

    renewal_fee = fields.Float(string='Estimated Renewal Fee (₹)', tracking=True)
    renewal_lead_time_days = fields.Integer(
        string='Renewal Lead Time (Days)',
        default=30,
        help='Standard time needed by government agency to process renewal'
    )

    company_id = fields.Many2one(
        'res.company',
        string='Company',
        default=lambda self: self.env.company,
        required=True
    )
    notes = fields.Html(string='Compliance Guidelines / Renewal Notes')

    # ── Constraints ───────────────────────────────────────────
    @api.constrains('issue_date', 'expiry_date')
    def _check_dates(self):
        for rec in self:
            if rec.issue_date and rec.expiry_date and rec.issue_date > rec.expiry_date:
                raise ValidationError(_('Expiry Date cannot be earlier than Issue Date!'))

    # ── Computations ──────────────────────────────────────────
    @api.depends('expiry_date')
    def _compute_days_to_expire(self):
        today = fields.Date.context_today(self)
        for rec in self:
            if rec.expiry_date:
                rec.days_to_expire = (rec.expiry_date - today).days
            else:
                rec.days_to_expire = 0

    @api.depends('days_to_expire', 'state')
    def _compute_status_and_alerts(self):
        for rec in self:
            if rec.state in ['draft', 'renewed', 'cancelled']:
                continue
            days = rec.days_to_expire
            if days < 0:
                rec.state = 'expired'
            elif days <= 7:
                rec.state = 'expiring_7'
            elif days <= 15:
                rec.state = 'expiring_15'
            elif days <= 30:
                rec.state = 'expiring_30'
            else:
                rec.state = 'active'

    # ── Actions ───────────────────────────────────────────────
    def action_activate(self):
        for rec in self:
            rec.state = 'active'
            rec._compute_status_and_alerts()
            rec.message_post(body=_('Certificate activated into compliance monitoring.'))

    def action_reset_draft(self):
        for rec in self:
            rec.state = 'draft'
            rec.alert_stage = 'none'

    def action_cancel(self):
        for rec in self:
            rec.state = 'cancelled'

    def action_renew(self):
        """Mark current certificate as renewed and prepare a new draft certificate"""
        self.ensure_one()
        self.state = 'renewed'
        self.message_post(body=_('Certificate marked as Renewed/Superseded.'))

        # Create copy for the next cycle
        new_cert = self.copy({
            'name': self.name,
            'certificate_no': self.certificate_no,
            'issue_date': fields.Date.context_today(self),
            'expiry_date': fields.Date.context_today(self) + timedelta(days=365),
            'state': 'draft',
            'alert_stage': 'none',
            'certificate_file': False,
            'file_name': False,
        })
        return {
            'name': _('Renewed Certificate'),
            'type': 'ir.actions.act_window',
            'res_model': 'compliance.certificate',
            'res_id': new_cert.id,
            'view_mode': 'form',
            'target': 'current',
        }

    # ── Expiry Alert & Scheduled Cron Engine ──────────────────
    @api.model
    def cron_check_certificate_expiry(self):
        """Scheduled daily action: scan all certificates and send tiered alerts"""
        today = fields.Date.context_today(self)
        certificates = self.search([
            ('state', 'not in', ['draft', 'renewed', 'cancelled']),
            ('expiry_date', '!=', False)
        ])

        for cert in certificates:
            cert._compute_days_to_expire()
            days = cert.days_to_expire

            # 1. EXPIRED (< 0 days)
            if days <= 0:
                cert.state = 'expired'
                if cert.alert_stage != 'expired_alert':
                    cert._trigger_compliance_alert(
                        level='EXPIRED',
                        days=days,
                        mail_xml_id='l4e_certificate_master.email_template_cert_expired',
                        activity_note=_('CRITICAL: Certificate %s has EXPIRED! Immediate renewal or shutdown protocol required.') % cert.name
                    )
                    cert.alert_stage = 'expired_alert'

            # 2. CRITICAL (<= 7 days)
            elif days <= 7:
                cert.state = 'expiring_7'
                if cert.alert_stage not in ['alert_7', 'expired_alert']:
                    cert._trigger_compliance_alert(
                        level='7_DAYS',
                        days=days,
                        mail_xml_id='l4e_certificate_master.email_template_cert_7_days',
                        activity_note=_('URGENT: Certificate %s will expire in %s days. Complete renewal immediately.') % (cert.name, days)
                    )
                    cert.alert_stage = 'alert_7'

            # 3. URGENT (<= 15 days)
            elif days <= 15:
                cert.state = 'expiring_15'
                if cert.alert_stage not in ['alert_15', 'alert_7', 'expired_alert']:
                    cert._trigger_compliance_alert(
                        level='15_DAYS',
                        days=days,
                        mail_xml_id='l4e_certificate_master.email_template_cert_15_days',
                        activity_note=_('WARNING: Certificate %s expires in %s days. Verify documents with authority.') % (cert.name, days)
                    )
                    cert.alert_stage = 'alert_15'

            # 4. ADVANCE NOTICE (<= 30 days)
            elif days <= 30:
                cert.state = 'expiring_30'
                if cert.alert_stage == 'none':
                    cert._trigger_compliance_alert(
                        level='30_DAYS',
                        days=days,
                        mail_xml_id='l4e_certificate_master.email_template_cert_30_days',
                        activity_note=_('NOTICE: Certificate %s expires in %s days. Initiate renewal dossier.') % (cert.name, days)
                    )
                    cert.alert_stage = 'alert_30'

            # 5. Normal Active (> 30 days)
            else:
                cert.state = 'active'

    def _trigger_compliance_alert(self, level, days, mail_xml_id, activity_note):
        """Sends mail template and schedules a high-priority activity"""
        self.ensure_one()

        # Send Email
        try:
            template = self.env.ref(mail_xml_id, raise_if_not_found=False)
            if template:
                template.send_mail(self.id, force_send=True)
        except Exception as e:
            self.message_post(body=_('Automated alert email failed to send: %s') % str(e))

        # Schedule Activity for Responsible Person
        activity_type = self.env.ref('mail.mail_activity_data_todo', raise_if_not_found=False)
        if activity_type and self.responsible_id:
            # Check if pending activity already exists for this certificate
            existing_act = self.env['mail.activity'].search([
                ('res_model', '=', 'compliance.certificate'),
                ('res_id', '=', self.id),
                ('user_id', '=', self.responsible_id.id),
            ], limit=1)
            if not existing_act:
                self.activity_schedule(
                    activity_type_id=activity_type.id,
                    summary=_('Compliance Alert: %s (%s days left)') % (self.name, days),
                    note=activity_note,
                    user_id=self.responsible_id.id,
                    date_deadline=self.expiry_date
                )

        # Log into chatter
        body_msg = _(
            '<b>Compliance %s Alert Triggered!</b><br/>'
            'Days Remaining: <b>%s</b><br/>'
            'Responsible: %s'
        ) % (level.replace('_', ' '), days, self.responsible_id.name)
        self.message_post(body=body_msg, subtype_xmlid='mail.mt_note')

    def action_manual_trigger_alert(self):
        """Allows testing the alert manually from the form view"""
        self.ensure_one()
        self._compute_days_to_expire()
        self.cron_check_certificate_expiry()
        return {
            'type': 'ir.actions.client',
            'tag': 'display_notification',
            'params': {
                'title': _('Alert Check Completed'),
                'message': _('Alert status re-evaluated for %s. Remaining days: %s.') % (self.name, self.days_to_expire),
                'type': 'info',
                'sticky': False,
            }
        }
