from datetime import datetime, time
import pytz
from odoo import api, models


class ReportWeeklyChiller(models.AbstractModel):
    _name = 'report.l4e_weekly_chiller_report.report_weekly_chiller_document'
    _description = 'Weekly Chiller Task Report Document'

    @api.model
    def _get_report_values(self, docids, data=None):
        if not data or 'form' not in data:
            wizard = self.env['weekly.chiller.report.wizard'].browse(docids)
            data = {'form': wizard.read()[0]}

        form = data.get('form', {})
        date_from = form.get('date_from')
        date_to = form.get('date_to')
        team_ids = form.get('team_ids') or []
        employee_ids = form.get('employee_ids') or []

        # Domain to find chiller update visits
        domain = [('purpose', '=', 'chiller_update')]

        # Timezone conversion for accurate datetime boundaries
        user_tz = self.env.user.tz or 'Asia/Kolkata'
        try:
            tz = pytz.timezone(user_tz)
        except Exception:
            tz = pytz.timezone('Asia/Kolkata')

        if date_from:
            try:
                d_from = datetime.strptime(str(date_from), '%Y-%m-%d').date()
                dt_from = tz.localize(datetime.combine(d_from, time.min)).astimezone(pytz.utc).replace(tzinfo=None)
                domain.append(('check_in_at', '>=', dt_from))
            except Exception:
                pass

        if date_to:
            try:
                d_to = datetime.strptime(str(date_to), '%Y-%m-%d').date()
                dt_to = tz.localize(datetime.combine(d_to, time.max)).astimezone(pytz.utc).replace(tzinfo=None)
                domain.append(('check_in_at', '<=', dt_to))
            except Exception:
                pass

        if employee_ids:
            domain.append(('employee_id', 'in', employee_ids))
        elif team_ids:
            domain.append(('employee_id.ff_team_id', 'in', team_ids))

        visits = self.env['ff.visit'].sudo().search(domain, order='check_in_at asc, employee_id asc, id asc')

        rows = []
        for visit in visits:
            # Format date as DD-MM-YYYY in user timezone
            if visit.check_in_at:
                local_dt = pytz.utc.localize(visit.check_in_at).astimezone(tz)
                date_str = local_dt.strftime('%d-%m-%Y')
            else:
                date_str = ''

            # Fetch photo attachment linked to this visit
            attachment = self.env['ir.attachment'].sudo().search([
                ('res_model', '=', 'ff.visit'),
                ('res_id', '=', visit.id),
                ('mimetype', 'like', 'image/%'),
            ], order='id desc', limit=1)

            photo_b64 = False
            mimetype = 'image/jpeg'
            if attachment and attachment.datas:
                raw_data = attachment.datas
                photo_b64 = raw_data.decode('utf-8') if isinstance(raw_data, bytes) else raw_data
                mimetype = attachment.mimetype or 'image/jpeg'

            emp_name = (visit.employee_id.name or '').upper()
            client_name = visit.partner_id.name or ''
            team_name = visit.team_id.name or (visit.employee_id.ff_team_id.name if visit.employee_id.ff_team_id else '')

            rows.append({
                'date': date_str,
                'employee_name': emp_name,
                'client_name': client_name,
                'photo_b64': photo_b64,
                'photo_mimetype': mimetype,
                'team_name': team_name,
            })

        # Header date range string (e.g. "21 Sep 2026 to 26 Sep 2026")
        try:
            d_from_obj = datetime.strptime(str(date_from), '%Y-%m-%d')
            d_to_obj = datetime.strptime(str(date_to), '%Y-%m-%d')
            date_range_str = f"{d_from_obj.strftime('%d %b %Y')} to {d_to_obj.strftime('%d %b %Y')}"
        except Exception:
            date_range_str = f"{date_from} to {date_to}"

        # Current generation timestamp in user timezone
        now_local = pytz.utc.localize(datetime.utcnow()).astimezone(tz)
        generated_at_str = now_local.strftime('%d %b %Y, %I:%M %p')

        return {
            'doc_ids': docids,
            'doc_model': 'weekly.chiller.report.wizard',
            'docs': visits,
            'rows': rows,
            'date_range': date_range_str,
            'generated_at': generated_at_str,
        }
