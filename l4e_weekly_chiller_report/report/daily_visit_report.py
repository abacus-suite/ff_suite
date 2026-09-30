from datetime import datetime, time
import pytz
from odoo import api, models


class ReportDailyVisit(models.AbstractModel):
    _name = 'report.l4e_weekly_chiller_report.report_daily_visit_document'
    _description = 'Daily Visit Report Document'

    @api.model
    def _get_report_values(self, docids, data=None):
        if not data or 'form' not in data:
            wizard = self.env['daily.visit.report.wizard'].browse(docids)
            data = {'form': wizard.read()[0]}

        form = data.get('form', {})
        date_from = form.get('date_from')
        date_to = form.get('date_to')
        team_ids = form.get('team_ids') or []
        employee_ids = form.get('employee_ids') or []

        # Domain to find visits
        domain = []

        # Timezone conversion
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
            # Format Date as DD-MM-YYYY
            if visit.check_in_at:
                local_check_in = pytz.utc.localize(visit.check_in_at).astimezone(tz)
                date_str = local_check_in.strftime('%d-%m-%Y')
                start_time_str = local_check_in.strftime('%d-%m-%Y %I:%M:%S %p')
            else:
                date_str = ''
                start_time_str = ''

            # Format Check-out / Exit times
            if visit.check_out_at:
                local_check_out = pytz.utc.localize(visit.check_out_at).astimezone(tz)
                end_time_str = local_check_out.strftime('%d-%m-%Y %I:%M:%S %p')
                exit_time_str = local_check_out.strftime('%d-%m-%Y %I:%M:%S %p')
            else:
                end_time_str = ''
                exit_time_str = ''

            # Fetch photos (up to 2 pictures)
            attachments = self.env['ir.attachment'].sudo().search([
                ('res_model', '=', 'ff.visit'),
                ('res_id', '=', visit.id),
                ('mimetype', 'like', 'image/%'),
            ], order='id asc', limit=2)

            photo1_b64 = False
            photo1_mimetype = 'image/jpeg'
            photo2_b64 = False
            photo2_mimetype = 'image/jpeg'

            if len(attachments) >= 1 and attachments[0].datas:
                raw1 = attachments[0].datas
                photo1_b64 = raw1.decode('utf-8') if isinstance(raw1, bytes) else raw1
                photo1_mimetype = attachments[0].mimetype or 'image/jpeg'

            if len(attachments) >= 2 and attachments[1].datas:
                raw2 = attachments[1].datas
                photo2_b64 = raw2.decode('utf-8') if isinstance(raw2, bytes) else raw2
                photo2_mimetype = attachments[1].mimetype or 'image/jpeg'

            emp_name = (visit.employee_id.name or '').upper()
            client_name = visit.partner_id.name or ''
            task_desc = visit.note or ''
            territory = getattr(visit.partner_id, 'x_studio_territory', '') or ''
            city = visit.partner_id.city or ''

            rows.append({
                'date': date_str,
                'employee_name': emp_name,
                'client_name': client_name,
                'task_description': task_desc,
                'photo1_b64': photo1_b64,
                'photo1_mimetype': photo1_mimetype,
                'photo2_b64': photo2_b64,
                'photo2_mimetype': photo2_mimetype,
                'start_time': start_time_str,
                'end_time': end_time_str,
                'exit_time': exit_time_str,
                'territory': territory,
                'city': city,
            })

        # Dynamic title based on employee(s)
        if len(employee_ids) == 1:
            emp = self.env['hr.employee'].sudo().browse(employee_ids[0])
            name_parts = emp.name.split() if emp.name else []
            display_name = name_parts[0] if name_parts else 'Employee'
            report_title = f"{display_name} Daily Reports"
        else:
            report_title = "Daily Reports"

        # Date range string
        try:
            d_from_obj = datetime.strptime(str(date_from), '%Y-%m-%d')
            d_to_obj = datetime.strptime(str(date_to), '%Y-%m-%d')
            date_range_str = f"{d_from_obj.strftime('%d %b %Y')} to {d_to_obj.strftime('%d %b %Y')}"
        except Exception:
            date_range_str = f"{date_from} to {date_to}"

        now_local = pytz.utc.localize(datetime.utcnow()).astimezone(tz)
        generated_at_str = now_local.strftime('%d %b %Y, %I:%M %p')

        return {
            'doc_ids': docids,
            'doc_model': 'daily.visit.report.wizard',
            'docs': visits,
            'report_title': report_title,
            'rows': rows,
            'date_range': date_range_str,
            'generated_at': generated_at_str,
        }
