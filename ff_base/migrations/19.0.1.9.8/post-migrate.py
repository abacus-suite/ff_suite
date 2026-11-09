"""Region became many: every employee keeps the Region they had, now as the first of their Regions."""


def migrate(cr, version):
    cr.execute("""
        INSERT INTO ff_employee_team_rel (employee_id, team_id)
        SELECT id, ff_team_id FROM hr_employee WHERE ff_team_id IS NOT NULL
        ON CONFLICT DO NOTHING
    """)
