/// Which Manager Mode screens a manager sees where two versions exist.
///
/// `false` (default): the manager-mode screens built on the `aj` branch: the team dashboard on Home,
/// the team-by-level My Team page and its Employee report with Visits / Tasks / day-wise pages.
/// `true`: the screens your lead built (`ManagerHome`, `MyTeamScreen`, `ManagerEmployeeReportScreen`).
///
/// Flip it and rebuild to compare the two side by side. Everything else (mode switch, Approvals,
/// Assign Task / Target, the bottom bar) is shared.
const bool kUseLeadManagerUi = false;
