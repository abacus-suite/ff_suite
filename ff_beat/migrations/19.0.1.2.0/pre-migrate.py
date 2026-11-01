"""Several routes per day are now allowed: drop the old one-plan-per-day constraint."""


def migrate(cr, version):
    for name in ('ff_beat_plan_employee_date_uniq', 'ff_beat_plan__employee_date_uniq'):
        cr.execute('ALTER TABLE ff_beat_plan DROP CONSTRAINT IF EXISTS "%s"' % name)
