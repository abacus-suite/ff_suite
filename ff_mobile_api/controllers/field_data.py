"""JSON serialisers for clients, visits and beat plans."""
from odoo.addons.ff_base.tools import haversine_m, to_iso

from .common import ref


def partner_commercials(partner):
    """What an outlet was agreed: its price category (149 / 179, from its territory), the scheme off every
    bottle and its margin. The rate of a product is the server's: (MRP - scheme) less the margin %."""
    if not partner:
        return None
    p = partner.sudo().commercial_partner_id
    option = p.ff_scheme_id if 'ff_scheme_id' in p._fields else False
    scheme = option.ff_scheme_value() if option and hasattr(option, 'ff_scheme_value') else 0.0
    territory = p.ff_territory_id if 'ff_territory_id' in p._fields else False
    category = territory.ff_price_category if territory and 'ff_price_category' in territory._fields else False
    margin = (p.ff_margin if 'ff_margin' in p._fields else 0.0) or 0.0
    if not margin and 'ff_distributor_id' in p._fields and p.ff_distributor_id:
        pass_through = getattr(p.env['product.product'], '_ff_pass_through_margin', None)
        margin = pass_through(p.ff_distributor_id.sudo().commercial_partner_id) if pass_through else 0.0
    if not (category or scheme or margin):
        return None
    return {'price_category': category or None, 'scheme_per_bottle': scheme or None,
            'margin_percent': margin or None}


def has_location(partner):
    return bool(partner.partner_latitude or partner.partner_longitude)


def partner_is_company_location(partner, employee=None):
    """Whether this client belongs to a territory with Company Location enabled."""
    if not partner:
        return False
    p = partner.sudo()
    Territory = partner.env['ff.territory'].sudo() if 'ff.territory' in partner.env else None
    if Territory:
        terrs = Territory.browse()
        if 'ff_territory_id' in p._fields and p.ff_territory_id:
            terrs |= p.ff_territory_id.sudo()
        if 'ff_secondary_territory_ids' in p._fields and p.ff_secondary_territory_ids:
            terrs |= p.ff_secondary_territory_ids.sudo()
        if 'ff_route_ids' in p._fields and p.ff_route_ids and 'territory_id' in p.ff_route_ids._fields:
            terrs |= p.ff_route_ids.sudo().mapped('territory_id')
        if 'ff_beat_line_ids' in p._fields and p.ff_beat_line_ids:
            terrs |= p.ff_beat_line_ids.sudo().mapped('beat_id.territory_id')
        for t in terrs:
            if getattr(t, 'is_company_location', False):
                return True

    if employee:
        emp = employee.sudo()
        if hasattr(emp, '_ff_has_company_location') and emp._ff_has_company_location():
            return True

    return False


def client_data(partner, lat=None, lng=None):
    located = has_location(partner)
    districts = []
    if 'ff_district_id' in partner._fields and partner.ff_district_id:
        districts.append(partner.ff_district_id)
    if 'ff_secondary_district_ids' in partner._fields and partner.ff_secondary_district_ids:
        seen_d = {d.id for d in districts}
        for d in partner.ff_secondary_district_ids:
            if d.id not in seen_d:
                seen_d.add(d.id)
                districts.append(d)

    territory = partner.ff_territory_id if 'ff_territory_id' in partner._fields and partner.ff_territory_id \
        else (partner.ff_route_ids[:1].territory_id if partner.ff_route_ids[:1]
              and 'territory_id' in partner.ff_route_ids._fields and partner.ff_route_ids[:1].territory_id else None)

    territories = []
    if 'ff_territory_id' in partner._fields and partner.ff_territory_id:
        territories.append(partner.ff_territory_id)
    if 'ff_secondary_territory_ids' in partner._fields and partner.ff_secondary_territory_ids:
        seen_t = {t.id for t in territories}
        for t in partner.ff_secondary_territory_ids:
            if t.id not in seen_t:
                seen_t.add(t.id)
                territories.append(t)
    if not territories and territory:
        territories.append(territory)
    # The app's Territory is the District / Territory master: the contact's own, then its secondary ones.
    if 'ff_district_id' in partner._fields and partner.ff_district_id:
        territory = partner.ff_district_id
        territories = [partner.ff_district_id] + [
            d for d in partner.ff_secondary_district_ids if d != partner.ff_district_id]

    is_company_loc = partner_is_company_location(partner)

    return {
        'id': partner.id,
        'name': partner.name,
        'code': partner.ff_client_code or None,
        'phone': partner.phone or None,
        'email': partner.email or None,
        'address': ', '.join(x for x in (partner.street, partner.street2, partner.city, partner.zip) if x) or None,
        'lat': partner.partner_latitude if located else None,
        'lng': partner.partner_longitude if located else None,
        'geofence_radius': partner._ff_radius(),
        'approval_state': partner.ff_approval_state,
        'category': ref(partner.ff_category_id),
        'category_type': partner.ff_category_type or ('distributor' if partner.ff_is_distributor else None),
        'risk_level': getattr(partner, 'ff_risk_level', None) or 'low',
        'is_distributor': bool(partner.ff_is_distributor or partner.ff_category_type == 'distributor'),
        'is_company_location': is_company_loc,
        'district': ref(partner.ff_district_id),
        'secondary_districts': [ref(d) for d in partner.ff_secondary_district_ids] if 'ff_secondary_district_ids' in partner._fields else [],
        'districts': [ref(d) for d in districts],
        'parent': ref(partner.parent_id),
        'last_visit_at': to_iso(partner.ff_last_visit_at),
        'last_visit_by': ref(partner.ff_last_visit_employee_id),
        'days_since_visit': partner.ff_days_since_visit if partner.ff_days_since_visit >= 0 else None,
        'routes': [ref(route) for route in partner.ff_route_ids],
        'territory': ref(territory),
        # The region: the one on the contact, else that of whoever added it.
        'region': ref(partner.ff_team_ids[:1]) if 'ff_team_ids' in partner._fields and partner.ff_team_ids
        else ref(partner.ff_created_by_employee_id.ff_team_id),
        'secondary_territories': [ref(t) for t in partner.ff_secondary_territory_ids] if 'ff_secondary_territory_ids' in partner._fields else [],
        'territories': [ref(t) for t in territories],
        'assigned_to': [ref(person) for person in partner.ff_employee_ids[:3]],
        'gst': partner.vat or None,
        'commercials': partner_commercials(partner) if getattr(partner, 'ff_category_type', None) == 'outlet' else None,
        'onboard_pending': getattr(partner, 'ff_status', None) == 'onboard_pending',
        'onboarded': getattr(partner, 'ff_status', None) == 'onboarded',
        'city': partner.city or None,
        # The area filter of the outlet lists: the contact's Area, else its City / District, else the city typed on it.
        'area': (ref(partner.ff_area_id) if 'ff_area_id' in partner._fields and partner.ff_area_id else None)
                or (ref(partner.ff_district_id) if partner.ff_district_id else None) or partner.city or None,
        # Only the Area master, for grouping: no fall back to the city here.
        'area_master': ref(partner.ff_area_id) if 'ff_area_id' in partner._fields and partner.ff_area_id else None,
        'zip': partner.zip or None,
        'street': partner.street or None,
        'distance_m': int(haversine_m(lat, lng, partner.partner_latitude, partner.partner_longitude))
        if located and lat is not None and lng is not None else None,
    }


def visit_data(visit):
    if not visit:
        return None
    return {
        'id': visit.id,
        'client': ref(visit.partner_id),
        'state': visit.state,
        'check_in_at': to_iso(visit.check_in_at),
        'check_out_at': to_iso(visit.check_out_at),
        'duration_min': visit.duration_min,
        'lat': visit.check_in_lat,
        'lng': visit.check_in_lng,
        'distance_m': visit.distance_m,
        'inside_geofence': visit.inside_geofence,
        'location_captured': visit.location_captured,
        'visit_type': visit.visit_type,
        'auto_start': visit.auto_start,
        'outcome': visit.outcome or None,
        'purpose': visit.purpose or None,
        # Which of the sales tasks the visit was opened for, where that module is installed.
        'task': getattr(visit, 'task_code', None) or None,
        'outcome_type': ref(visit.outcome_id),
        'productive': visit.productive,
        'note': visit.note or None,
        'photo_count': visit.photo_count,
        'is_planned': visit.is_planned,
    }


def plan_data(plan):
    if not plan:
        return None
    return {
        'id': plan.id,
        'date': plan.date.isoformat(),
        'beat': ref(plan.beat_id),
        'beat_code': plan.beat_id.code or None,
        # Who drew the beat: only the person who drew it may take it off a day. A beat nobody drew in the app
        # was given by the office or the manager.
        'added_by': ref(plan.beat_id.ff_created_by_employee_id) or ({'id': 0, 'name': 'Office'} if plan.beat_id else None),
        'assigned_by_manager': bool(plan.beat_id and plan.beat_id.ff_created_by_employee_id != plan.employee_id),
        'route_type': plan.beat_id.route_type_id.name or None,
        'month_plan': ref(plan.plan_id),
        'missed_count': plan.missed_count,
        'cancelled_count': plan.cancelled_count,
        'planned_count': plan.planned_count,
        'completed_count': plan.completed_count,
        'adhoc_count': plan.adhoc_count,
        'completion_pct': round(plan.completion_pct, 1),
        'planned_km': round(plan.planned_km, 1),
        'actual_km': round(plan.actual_km, 1),
        'status': plan.status,
    }
