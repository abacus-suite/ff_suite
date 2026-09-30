from datetime import datetime, time
import pytz
from odoo import api, models


FLAVOR_KEYS = ['AM', 'BM', 'LR', 'MS', 'OG', 'PB', 'BD', 'GG', 'CG']


class ReportVisitsOrders(models.AbstractModel):
    _name = 'report.l4e_client_visits_orders_report.report_visits_orders_doc'
    _description = 'Client Visits & Associated Orders Report Document'

    @api.model
    def _get_report_values(self, docids, data=None):
        if not data or 'form' not in data:
            wizard = self.env['visits.orders.report.wizard'].browse(docids)
            data = {'form': wizard.read()[0]}

        form = data.get('form', {})
        date_from = form.get('date_from')
        date_to = form.get('date_to')
        team_ids = form.get('team_ids') or []
        employee_ids = form.get('employee_ids') or []

        # Timezone conversion
        user_tz = self.env.user.tz or 'Asia/Kolkata'
        try:
            tz = pytz.timezone(user_tz)
        except Exception:
            tz = pytz.timezone('Asia/Kolkata')

        domain = []
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
            # Format Date and Times
            if visit.check_in_at:
                local_check_in = pytz.utc.localize(visit.check_in_at).astimezone(tz)
                date_str = local_check_in.strftime('%d-%m-%Y')
                start_time_str = local_check_in.strftime('%d-%m-%Y %I:%M:%S %p')
            else:
                date_str = ''
                start_time_str = ''

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
            task_uuid = visit.client_uuid or f"VISIT-{visit.id}"
            client_name = visit.partner_id.name or ''
            task_desc = visit.note or ''
            team_name = (visit.team_id.name or (visit.employee_id.ff_team_id.name if visit.employee_id.ff_team_id else '')).upper()

            # Find Associated Orders (sale.order or ff.demand)
            order_items = []

            # 1. Direct Sale Orders
            if 'sale.order' in self.env:
                orders = self.env['sale.order'].sudo().search([
                    ('ff_visit_id', '=', visit.id),
                    ('state', '!=', 'cancel'),
                ])
                for order in orders:
                    for line in order.order_line:
                        if line.product_id:
                            sku_name = line.product_id.name or ''
                            sku_code = (getattr(line.product_id.product_tmpl_id, 'ff_sku_code', '') or '').strip().upper()
                            qty = int(line.product_uom_qty) if line.product_uom_qty.is_integer() else line.product_uom_qty
                            order_items.append({'sku_name': sku_name, 'sku_code': sku_code, 'qty': qty})

            # 2. Outlet Demands
            if 'ff.demand' in self.env:
                demands = self.env['ff.demand'].sudo().search([
                    ('visit_id', '=', visit.id),
                    ('state', '!=', 'cancelled'),
                ])
                for demand in demands:
                    for dline in demand.line_ids:
                        if dline.product_id:
                            sku_name = dline.product_id.name or ''
                            sku_code = (getattr(dline.product_id.product_tmpl_id, 'ff_sku_code', '') or '').strip().upper()
                            qty = int(dline.qty) if isinstance(dline.qty, float) and dline.qty.is_integer() else dline.qty
                            order_items.append({'sku_name': sku_name, 'sku_code': sku_code, 'qty': qty})

            # If items exist, create a row for each item
            if order_items:
                for idx, item in enumerate(order_items):
                    item_sku_code = item['sku_code']
                    flavors = {}
                    for fk in FLAVOR_KEYS:
                        flavors[fk] = ''
                    if item_sku_code in flavors:
                        flavors[item_sku_code] = item['qty']

                    rows.append({
                        'employee_name': emp_name,
                        'task_id': task_uuid,
                        'date': date_str,
                        'client_name': client_name,
                        'task_description': task_desc,
                        'sku_name': item['sku_name'],
                        'item_qty': item['qty'],
                        'total_cs': '',
                        'flavors': flavors,
                        'photo1_b64': photo1_b64,
                        'photo1_mimetype': photo1_mimetype,
                        'photo2_b64': photo2_b64,
                        'photo2_mimetype': photo2_mimetype,
                        'start_time': start_time_str,
                        'exit_time': exit_time_str,
                        'end_time': end_time_str,
                        'team_name': team_name,
                    })
            else:
                # No order lines: single row with empty SKU info
                flavors = {fk: '' for fk in FLAVOR_KEYS}
                rows.append({
                    'employee_name': emp_name,
                    'task_id': task_uuid,
                    'date': date_str,
                    'client_name': client_name,
                    'task_description': task_desc,
                    'sku_name': '',
                    'item_qty': '',
                    'total_cs': '',
                    'flavors': flavors,
                    'photo1_b64': photo1_b64,
                    'photo1_mimetype': photo1_mimetype,
                    'photo2_b64': photo2_b64,
                    'photo2_mimetype': photo2_mimetype,
                    'start_time': start_time_str,
                    'exit_time': exit_time_str,
                    'end_time': end_time_str,
                    'team_name': team_name,
                })

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
            'doc_model': 'visits.orders.report.wizard',
            'docs': visits,
            'rows': rows,
            'flavor_keys': FLAVOR_KEYS,
            'date_range': date_range_str,
            'generated_at': generated_at_str,
        }
