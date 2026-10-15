import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../core/services.dart';
import '../../core/theme.dart';
import 'overdue_screen.dart';
import '../tasks/tasks_screen.dart';

Widget _shell(String title, IconData icon, Widget child, {Widget? trailing}) => Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        boxShadow: [BoxShadow(color: const Color(0xFF1B3A7A).withValues(alpha: 0.06), blurRadius: 12, offset: const Offset(0, 4))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(icon, size: 19, color: AppColors.primary),
          const SizedBox(width: 8),
          Expanded(child: Text(title, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15.5))),
          if (trailing != null) trailing,
        ]),
        const SizedBox(height: 12),
        child,
      ]),
    );

/// What the team's month looks like against its targets: one bar per target.
///
/// Reads `target` from the team dashboard: a list of `{label, achieved, target}`. Shows a hint until the server sends it.
class TeamTargetCard extends StatelessWidget {
  const TeamTargetCard({super.key, required this.targets, required this.monthLabel});

  final List<Map<String, dynamic>> targets;
  final String monthLabel;

  @override
  Widget build(BuildContext context) {
    if (targets.isEmpty) {
      return _shell(
        'Team Target – $monthLabel',
        Icons.track_changes_rounded,
        const Text('No team target has been set for this month yet. Set one from Tasks → Assign → Assign Target.',
            style: TextStyle(fontSize: 12, color: AppColors.muted)),
      );
    }
    return _shell(
      'Team Target – $monthLabel',
      Icons.track_changes_rounded,
      Column(children: [
        for (final t in targets) ...[
          Builder(builder: (_) {
            final goal = (t['target'] as num?)?.toDouble() ?? 0;
            final got = (t['achieved'] as num?)?.toDouble() ?? 0;
            final pct = goal <= 0 ? 0.0 : got / goal;
            return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(child: Text('${t['label']}', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5))),
                Text('${(pct * 100).round()}%', style: const TextStyle(fontWeight: FontWeight.w800, color: AppColors.warning)),
              ]),
              const SizedBox(height: 4),
              ClipRRect(
                borderRadius: BorderRadius.circular(5),
                child: LinearProgressIndicator(value: pct.clamp(0.0, 1.0), minHeight: 8, backgroundColor: AppColors.border, color: AppColors.warning),
              ),
              const SizedBox(height: 3),
              Text('${fmtCompact(got)} of ${fmtCompact(goal)}', style: const TextStyle(fontSize: 11, color: AppColors.muted)),
              const SizedBox(height: 10),
            ]);
          }),
        ],
      ]),
    );
  }

  static String fmtCompact(double v) => v == v.roundToDouble() ? v.round().toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ',') : v.toStringAsFixed(1);
}

/// Planned / Visited / Pending / Cancelled for the team's beat plans, with a way in to who owes what.
class BeatPlanSummaryCard extends StatelessWidget {
  const BeatPlanSummaryCard({super.key, required this.planned, required this.visited, required this.cancelled, this.onViewAll});

  final num planned;
  final num visited;
  final num cancelled;
  final VoidCallback? onViewAll;

  @override
  Widget build(BuildContext context) {
    final pending = (planned - visited - cancelled).clamp(0, double.infinity);
    Widget tile(String label, num v, Color c) {
      final pct = planned <= 0 ? 0 : (v / planned * 100).round();
      return Expanded(
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 3),
          padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
          decoration: BoxDecoration(color: c.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(14)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Align(alignment: Alignment.centerRight, child: Text('$pct%', style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w800, color: c))),
            Text('$v', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 20, color: Color(0xFF0F172A))),
            Text(label, style: const TextStyle(fontSize: 11, color: Color(0xFF334155))),
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(value: planned <= 0 ? 0 : (v / planned).clamp(0, 1).toDouble(), minHeight: 3, backgroundColor: Colors.white, color: c),
            ),
          ]),
        ),
      );
    }

    return _shell(
      'Team Beat Plan Summary',
      Icons.fact_check_rounded,
      Row(children: [
        tile('Planned', planned, AppColors.primary),
        tile('Visited', visited, AppColors.success),
        tile('Pending', pending, AppColors.warning),
        tile('Cancelled', cancelled, AppColors.danger),
      ]),
      trailing: onViewAll == null ? null : TextButton(onPressed: onViewAll, child: const Text('View All')),
    );
  }
}

/// Money the team's outlets and distributors still owe, past due.
class OverdueCard extends StatefulWidget {
  const OverdueCard({super.key});

  @override
  State<OverdueCard> createState() => _OverdueCardState();
}

class _OverdueCardState extends State<OverdueCard> {
  num? _outlet;
  num? _distributor;
  String? _currency;
  bool _done = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<num?> _one(String type) async {
    try {
      final d = await Services.api.get('/api/v1/receivables', query: {'filter': 'overdue', 'partner_type': type}) as Map<String, dynamic>;
      _currency ??= d['currency'] as String?;
      return (d['overdue'] as num?) ?? (d['total'] as num?);
    } catch (_) {
      return null;
    }
  }

  Future<void> _load() async {
    final r = await Future.wait([_one('outlet'), _one('distributor')]);
    if (!mounted) return;
    setState(() {
      _outlet = r[0];
      _distributor = r[1];
      _done = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_done || (_outlet == null && _distributor == null)) return const SizedBox.shrink();
    Widget part(String label, num? v, Color c, IconData icon) => Expanded(
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 3),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: c.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(14)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(icon, size: 16, color: c),
              const SizedBox(height: 4),
              FittedBox(child: Text(fmtMoney(v ?? 0, _currency), style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15, color: Color(0xFF0F172A)))),
              Text(label, style: const TextStyle(fontSize: 11, color: Color(0xFF334155))),
            ]),
          ),
        );
    return InkWell(
      borderRadius: BorderRadius.circular(22),
      onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const OverdueScreen())),
      child: _shell(
        'Overdue',
        Icons.receipt_long_rounded,
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(
              child: Text(fmtMoney((_outlet ?? 0) + (_distributor ?? 0), _currency),
                  style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 24, color: AppColors.danger)),
            ),
            const Text('By outlet, distributor', style: TextStyle(fontSize: 11, color: Color(0xFF334155))),
            const Icon(Icons.chevron_right_rounded, size: 18, color: Color(0xFF334155)),
          ]),
          const SizedBox(height: 10),
          Row(children: [
            part('Outlet overdue', _outlet, AppColors.primary, Icons.storefront_rounded),
            part('Distributor overdue', _distributor, AppColors.warning, Icons.local_shipping_rounded),
          ]),
        ]),
      ),
    );
  }
}

/// The tasks the manager has given out, with Pending / Done / Overdue to filter by.
class AssignedTasksCard extends StatefulWidget {
  const AssignedTasksCard({super.key});

  @override
  State<AssignedTasksCard> createState() => _AssignedTasksCardState();
}

class _AssignedTasksCardState extends State<AssignedTasksCard> {
  List<Map<String, dynamic>>? _tasks;
  String _chip = 'pending';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final d = await Services.api.get('/api/v1/tasks', query: {'scope': 'team'}) as Map<String, dynamic>;
      if (mounted) setState(() => _tasks = ((d['tasks'] as List?) ?? []).cast<Map<String, dynamic>>());
    } catch (_) {
      if (mounted) setState(() => _tasks = const []);
    }
  }

  bool _isDone(Map<String, dynamic> t) => t['state'] == 'done';
  bool _isOverdue(Map<String, dynamic> t) => !_isDone(t) && t['is_overdue'] == true;
  bool _isPending(Map<String, dynamic> t) => !_isDone(t) && t['state'] != 'cancelled';

  @override
  Widget build(BuildContext context) {
    final all = _tasks;
    if (all == null || all.isEmpty) return const SizedBox.shrink();
    final pending = all.where(_isPending).length;
    final done = all.where(_isDone).length;
    final overdue = all.where(_isOverdue).length;
    final shown = all.where((t) => switch (_chip) { 'done' => _isDone(t), 'overdue' => _isOverdue(t), _ => _isPending(t) }).take(3).toList();
    Widget chip(String key, String label, int n) => Padding(
          padding: const EdgeInsets.only(right: 8),
          child: ChoiceChip(
            label: Text('$label $n', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
            selected: _chip == key,
            visualDensity: VisualDensity.compact,
            onSelected: (_) => setState(() => _chip = key),
          ),
        );
    Color colour(Map<String, dynamic> t) => _isOverdue(t) ? AppColors.danger : _isDone(t) ? AppColors.success : AppColors.warning;
    String status(Map<String, dynamic> t) => _isOverdue(t) ? 'Overdue' : _isDone(t) ? 'Done' : 'Pending';
    void openTasks() => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const TasksScreen()));
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [chip('pending', 'Pending', pending), chip('done', 'Done', done), chip('overdue', 'Overdue', overdue)]),
        for (final t in shown)
          InkWell(
            onTap: openTasks,
            child: Container(
              margin: const EdgeInsets.only(top: 8),
              padding: const EdgeInsets.fromLTRB(12, 8, 10, 8),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(10),
                border: Border(left: BorderSide(color: colour(t), width: 3), top: const BorderSide(color: AppColors.border), right: const BorderSide(color: AppColors.border), bottom: const BorderSide(color: AppColors.border)),
              ),
              child: Row(children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('${t['name']}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5)),
                    Text('To: ${t['employee'] is Map ? (t['employee'] as Map)['name'] : t['employee'] ?? ''}${t['due'] != null ? ' · due ${t['due']}' : ''}',
                        style: const TextStyle(fontSize: 11, color: AppColors.muted)),
                  ]),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(color: colour(t), borderRadius: BorderRadius.circular(12)),
                  child: Text(status(t), style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, color: Colors.white)),
                ),
              ]),
            ),
          ),
        if (shown.isEmpty) const Padding(padding: EdgeInsets.all(8), child: Text('Nothing here.', style: TextStyle(color: AppColors.muted))),
        const SizedBox(height: 4),
        InkWell(
          onTap: openTasks,
          child: const Padding(
            padding: EdgeInsets.symmetric(horizontal: 4, vertical: 10),
            child: Row(children: [
              Expanded(child: Text('View all tasks', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5))),
              Icon(Icons.chevron_right_rounded, size: 18, color: AppColors.muted),
            ]),
          ),
        ),
      ]),
    );
  }
}

/// Work alerts for the team: things that need a manager's hand, each with the people involved.
///
/// Reads `work_alerts` from the team dashboard: a list of `{key, title, people: [name…], count}`.
class WorkAlertsCard extends StatelessWidget {
  const WorkAlertsCard({super.key, required this.alerts});

  final List<Map<String, dynamic>> alerts;

  static IconData _icon(String k) => switch (k) {
        'beat_not_planned' => Icons.event_busy_rounded,
        'missed_checkout' => Icons.access_time_rounded,
        'expenses_not_sent' => Icons.receipt_rounded,
        _ => Icons.notifications_active_rounded,
      };

  @override
  Widget build(BuildContext context) {
    if (alerts.isEmpty) return const SizedBox.shrink();
    return _shell(
      'Alerts',
      Icons.notifications_active_rounded,
      Column(children: [
        for (final a in alerts)
          Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: AppColors.background, borderRadius: BorderRadius.circular(12)),
            child: Row(children: [
              CircleAvatar(radius: 17, backgroundColor: AppColors.primary.withValues(alpha: 0.1), child: Icon(_icon('${a['key']}'), size: 17, color: AppColors.primary)),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${a['title']}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5)),
                  Text(((a['people'] as List?) ?? []).join(', '), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11, color: AppColors.muted)),
                ]),
              ),
              CircleAvatar(radius: 10, backgroundColor: AppColors.warning, child: Text('${a['count'] ?? ((a['people'] as List?) ?? []).length}', style: const TextStyle(fontSize: 10.5, color: Colors.white, fontWeight: FontWeight.w800))),
            ]),
          ),
      ]),
    );
  }
}
