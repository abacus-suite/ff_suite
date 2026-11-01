def migrate(cr, version):
    """Targets are no longer one per employee per month only: drop the old unique rule, mark old rows as employee targets."""
    cr.execute("ALTER TABLE ff_target DROP CONSTRAINT IF EXISTS ff_target_employee_month_uniq")
    cr.execute("SELECT 1 FROM information_schema.columns WHERE table_name = 'ff_target' AND column_name = 'scope'")
    if not cr.fetchone():
        cr.execute("ALTER TABLE ff_target ADD COLUMN scope varchar")
    cr.execute("UPDATE ff_target SET scope = 'employee' WHERE scope IS NULL")
