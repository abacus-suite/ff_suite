def migrate(cr, version):
    """Visits checked in outside the geofence before onsite/offsite existed count as offsite."""
    cr.execute("UPDATE ff_visit SET visit_type = 'offsite' WHERE inside_geofence IS NOT TRUE")
