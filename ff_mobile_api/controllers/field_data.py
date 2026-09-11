"""JSON serialisers for clients, visits and beat plans."""
from odoo.addons.ff_base.tools import haversine_m, to_iso

from .common import ref


def has_location(partner):
    return bool(partner.partner_latitude or partner.partner_longitude)


def client_data(partner, lat=None, lng=None):
    located = has_location(partner)
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
        'category_type': partner.ff_category_type or None,
        'district': ref(partner.ff_district_id),
        'parent': ref(partner.parent_id),
        'last_visit_at': to_iso(partner.ff_last_visit_at),
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
        'outcome': visit.outcome or None,
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
        'route_type': plan.beat_id.route_type_id.name or None,
        'planned_count': plan.planned_count,
        'completed_count': plan.completed_count,
        'adhoc_count': plan.adhoc_count,
        'completion_pct': round(plan.completion_pct, 1),
        'planned_km': round(plan.planned_km, 1),
        'actual_km': round(plan.actual_km, 1),
        'status': plan.status,
    }
