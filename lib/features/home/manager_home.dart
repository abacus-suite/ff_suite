import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/format.dart';
import '../../core/services.dart';
import '../../core/theme.dart';
import '../../widgets/common.dart';
import '../../widgets/skeleton.dart';
import '../approvals/approvals_screen.dart';
import '../tasks/tasks_screen.dart';
import '../team/assign_target_screen.dart';
import '../team/team_live_screen.dart';
import '../team/team_target_screen.dart';

/// Manager Mode Home: the team's attendance, approvals, beat plan, target, overdue, the tasks I gave,
/// alerts, and the live map at the bottom.
class ManagerHome extends StatefulWidget {
  const ManagerHome({super.key, required this.pending, this.onApprovalsClosed});

  /// How many approvals wait for this manager.
  final int pending;
  final VoidCallback? onApprovalsClosed;

  @override
  State<ManagerHome> createState() => _ManagerHomeState();
}

class _ManagerHomeState extends State<ManagerHome> {
  String _period = 'today';
  Map<String, dynamic>? _home;
  Map<String, dynamic>? _target;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    Services.refresh.addListener(_load);
    _load();
  }

  @override
  void dispose() {
    Services.refresh.removeListener(_load);
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final home = await Services.api.get('/api/v1/team/home', query: {'period': _period}) as Map<String, dynamic>;
      Map<String, dynamic>? target;
      try {
        target = await Services.api.get('/api/v1/team/target') as Map<String, dynamic>;
      } catch (_) {
        // The targets module may not be there: the card is simply left out.
      }
      if (mounted) {
        setState(() {
          _home = home;
          _target = target;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Map<String, dynamic> _block(String key) => (_home?[key] as Map?)?.cast<String, dynamic>() ?? const {};

  int _count(String key) => (((_block('attendance')[key] as Map?)?['count']) as num? ?? 0).toInt();

  List<Map<String, dynamic>> _people(String key) =>
      ((((_block('attendance')[key] as Map?)?['people']) as List?) ?? []).cast<Map<String, dynamic>>();

  Widget _card({required Widget child, EdgeInsets padding = const EdgeInsets.all(14)}) => Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: padding,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.border.withValues(alpha: 0.7)),
        ),
        child: child,
      );

  Widget _title(String text, {Widget? trailing}) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Row(children: [
          Expanded(child: Text(text, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15.5))),
          if (trailing != null) trailing,
        ]),
      );

  @override
  Widget build(BuildContext context) {
    if (_home == null) {
      return _error != null
          ? Card(child: ErrorView(message: _error!, onRetry: _load))
          : const Padding(padding: EdgeInsets.all(40), child: LoadingView());
    }
    return Column(children: [
      _attendance(),
      _approvals(),
      _beatPlan(),
      if (_target != null) _teamTarget(),
      _overdue(),
      _tasks(),
      _alerts(),
      _liveMap(),
    ]);
  }

  // ------------------------------------------------------------------ attendance
  Widget _attendance() {
    final team = ((_home?['team_size'] as num?) ?? 0).toInt();
    final present = _count('present');
    Widget chip(String key, String label) => Padding(
          padding: const EdgeInsets.only(right: 8),
          child: ChoiceChip(
            label: Text(label),
            selected: _period == key,
            onSelected: (_) {
              setState(() => _period = key);
              _load();
            },
          ),
        );
    Widget box(String key, String label, Color tint) => Expanded(
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => _PeopleScreen(title: '$label (${_count(key)})', people: _people(key), period: _period))),
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 3),
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(color: tint.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(14)),
              child: Column(children: [
                Text('${_count(key)}', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 20, color: tint)),
                Text(label, style: const TextStyle(fontSize: 11.5, color: AppColors.muted, fontWeight: FontWeight.w600)),
              ]),
            ),
          ),
        );
    return _card(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(children: [
            chip('today', 'Today'),
            chip('yesterday', 'Yesterday'),
            chip('week', 'This week'),
            chip('month', 'This month'),
          ]),
        ),
        const SizedBox(height: 10),
        Row(children: [
          Text('$present', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 30)),
          const SizedBox(width: 6),
          Text('of $team', style: const TextStyle(color: AppColors.muted)),
          const SizedBox(width: 12),
          const Expanded(
            child: Text('Your team today', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
          ),
        ]),
        const SizedBox(height: 10),
        Row(children: [
          box('present', 'Present', AppColors.success),
          box('late', 'Late', AppColors.warning),
          box('absent', 'Absent', AppColors.danger),
          box('leave', 'On Leave', AppColors.primary),
        ]),
        if (_loading) const Padding(padding: EdgeInsets.only(top: 8), child: LinearProgressIndicator(minHeight: 2)),
      ]),
    );
  }

  // ------------------------------------------------------------------ approvals
  Widget _approvals() => InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () async {
          await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ApprovalsScreen()));
          widget.onApprovalsClosed?.call();
        },
        child: Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: widget.pending > 0
                  ? const [Color(0xFFEA580C), Color(0xFFF59E0B)]
                  : const [Color(0xFF059669), Color(0xFF10B981)],
            ),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(children: [
            const Icon(Icons.fact_check_rounded, color: Colors.white, size: 26),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Approvals',
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 16.5)),
                Text(widget.pending > 0 ? '${widget.pending} waiting for you' : 'Nothing waiting for you',
                    style: const TextStyle(color: Colors.white, fontSize: 12.5)),
              ]),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18)),
              child: Text('${widget.pending}', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
            ),
            const Icon(Icons.chevron_right_rounded, color: Colors.white),
          ]),
        ),
      );

  // ------------------------------------------------------------------ beat plan
  Widget _beatPlan() {
    final b = _block('beat_plan');
    final planned = ((b['planned'] as num?) ?? 0).toInt();
    int n(String k) => ((b[k] as num?) ?? 0).toInt();
    String share(int v) => planned == 0 ? '0%' : '${(v * 100 / planned).round()}%';
    Widget tile(String label, int value, Color tint) => Expanded(
          child: Column(children: [
            Text('$value', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 19, color: tint)),
            Text(label, style: const TextStyle(fontSize: 11.5, color: AppColors.muted)),
            Text(share(value), style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: tint)),
          ]),
        );
    return _card(
      child: InkWell(
        onTap: () => Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => _BeatPlanScreen(people: ((b['people'] as List?) ?? []).cast<Map<String, dynamic>>()))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _title('Team Beat Plan Summary',
              trailing: const Text('View All', style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.w800))),
          Row(children: [
            tile('Planned', planned, AppColors.primary),
            tile('Visited', n('visited'), AppColors.success),
            tile('Pending', n('pending'), AppColors.warning),
            tile('Cancelled', n('cancelled'), AppColors.danger),
          ]),
        ]),
      ),
    );
  }

  // ------------------------------------------------------------------ team target
  Widget _teamTarget() {
    final t = _target!;
    final bottles = ((t['bottles'] as num?) ?? 0).toInt();
    final bottleTarget = ((t['bottle_target'] as num?) ?? 0).toInt();
    final outlets = ((t['outlets'] as num?) ?? 0).toInt();
    final outletTarget = ((t['outlet_target'] as num?) ?? 0).toInt();
    Widget bar(String label, int actual, int target) {
      final ratio = target == 0 ? 0.0 : (actual / target).clamp(0.0, 1.0);
      return Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text(label, style: const TextStyle(fontWeight: FontWeight.w700))),
            Text(target == 0 ? 'No target' : '${(ratio * 100).round()}%',
                style: const TextStyle(fontWeight: FontWeight.w900, color: AppColors.primary)),
          ]),
          const SizedBox(height: 5),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(value: ratio, minHeight: 9, backgroundColor: AppColors.border.withValues(alpha: 0.5)),
          ),
          const SizedBox(height: 3),
          Text('${fmtQty(actual)} of ${fmtQty(target)}', style: const TextStyle(fontSize: 12, color: AppColors.muted)),
        ]),
      );
    }

    final month = monthNames[DateTime.now().month - 1];
    return _card(
      child: InkWell(
        onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const TeamTargetScreen())),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _title('Team Target · $month (month to date)',
              trailing: const Icon(Icons.chevron_right_rounded, color: AppColors.muted)),
          bar('No. of bottles', bottles, bottleTarget),
          bar('No. of outlets onboarded', outlets, outletTarget),
        ]),
      ),
    );
  }

  // ------------------------------------------------------------------ overdue
  Widget _overdue() {
    final o = _block('overdue');
    final currency = _home?['currency'] as String?;
    final items = ((o['items'] as List?) ?? []).cast<Map<String, dynamic>>();
    return _card(
      child: InkWell(
        onTap: () => Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => _OverdueScreen(items: items, currency: currency))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _title('Overdue', trailing: const Icon(Icons.chevron_right_rounded, color: AppColors.muted)),
          Text(fmtMoney(o['total'] as num?, currency),
              style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 24, color: AppColors.danger)),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(
              child: _small('Outlet overdue', fmtMoney(o['outlet'] as num?, currency)),
            ),
            Expanded(
              child: _small('Distributor overdue', fmtMoney(o['distributor'] as num?, currency)),
            ),
          ]),
        ]),
      ),
    );
  }

  Widget _small(String label, String value) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(value, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
        Text(label, style: const TextStyle(fontSize: 12, color: AppColors.muted)),
      ]);

  // ------------------------------------------------------------------ tasks I gave
  Widget _tasks() {
    final t = _block('tasks');
    final latest = ((t['latest'] as List?) ?? []).cast<Map<String, dynamic>>();
    Widget pill(String label, num? v, Color tint) => Padding(
          padding: const EdgeInsets.only(right: 8),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(color: tint.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(20)),
            child: Text('$label ${v ?? 0}', style: TextStyle(fontWeight: FontWeight.w800, color: tint, fontSize: 12.5)),
          ),
        );
    return _card(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _title('Tasks assigned by me'),
        Row(children: [
          pill('Pending', t['pending'] as num?, AppColors.warning),
          pill('Done', t['done'] as num?, AppColors.success),
          pill('Overdue', t['overdue'] as num?, AppColors.danger),
        ]),
        const SizedBox(height: 8),
        for (final task in latest)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${task['name']}', maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                  Text('To: ${task['to']}${task['due'] != null ? ' · due ${task['due']}' : ''}',
                      style: const TextStyle(fontSize: 12, color: AppColors.muted)),
                ]),
              ),
              Text(task['status'] == 'overdue' ? 'Overdue' : 'Pending',
                  style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 12,
                      color: task['status'] == 'overdue' ? AppColors.danger : AppColors.warning)),
            ]),
          ),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton(
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const TasksScreen())),
            child: const Text('View all tasks'),
          ),
        ),
      ]),
    );
  }

  // ------------------------------------------------------------------ alerts
  Widget _alerts() {
    final alerts = ((_home?['alerts'] as List?) ?? []).cast<Map<String, dynamic>>();
    if (alerts.isEmpty) return const SizedBox.shrink();
    return _card(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _title('Alerts'),
        for (final a in alerts)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Icon(Icons.warning_amber_rounded, color: AppColors.warning, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${a['title']}', style: const TextStyle(fontWeight: FontWeight.w800)),
                  Text(((a['names'] as List?) ?? []).join(', '),
                      style: const TextStyle(fontSize: 12.5, color: AppColors.muted)),
                ]),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                decoration: BoxDecoration(color: AppColors.warning.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(12)),
                child: Text('${a['count']}', style: const TextStyle(fontWeight: FontWeight.w900, color: AppColors.warning)),
              ),
            ]),
          ),
      ]),
    );
  }

  // ------------------------------------------------------------------ live map
  Widget _liveMap() => _card(
        child: InkWell(
          onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const TeamLiveScreen())),
          child: Row(children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(color: AppColors.primary.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(14)),
              child: const Icon(Icons.map_rounded, color: AppColors.primary),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Live map', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15.5)),
                Text('Where your team is right now', style: TextStyle(fontSize: 12.5, color: AppColors.muted)),
              ]),
            ),
            const Icon(Icons.chevron_right_rounded, color: AppColors.muted),
          ]),
        ),
      );
}

/// A list of people for a status, each with the time they checked in and a call button.
class _PeopleScreen extends StatelessWidget {
  const _PeopleScreen({required this.title, required this.people, required this.period});

  final String title;
  final List<Map<String, dynamic>> people;
  final String period;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: people.isEmpty
          ? const Center(child: Text('Nobody here.', style: TextStyle(color: AppColors.muted)))
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                for (final p in people)
                  Card(
                    child: ListTile(
                      leading: CircleAvatar(
                        backgroundColor: AppColors.primary.withValues(alpha: 0.1),
                        child: Text('${p['name']}'.isEmpty ? '?' : '${p['name']}'[0].toUpperCase(),
                            style: const TextStyle(fontWeight: FontWeight.w900, color: AppColors.primary)),
                      ),
                      title: Text('${p['name']}', style: const TextStyle(fontWeight: FontWeight.w800)),
                      subtitle: Text([
                        if (p['in_at'] != null) 'In ${fmtTime(p['in_at'])}',
                        if (p['job'] != null) '${p['job']}',
                      ].join(' · ')),
                      trailing: p['phone'] == null
                          ? null
                          : IconButton(
                              icon: const Icon(Icons.call_rounded, color: AppColors.success),
                              onPressed: () => launchUrl(Uri(scheme: 'tel', path: '${p['phone']}')),
                            ),
                    ),
                  ),
              ],
            ),
    );
  }
}

/// Team Beat Plan: each person, the beats and how many visits are done.
class _BeatPlanScreen extends StatelessWidget {
  const _BeatPlanScreen({required this.people});

  final List<Map<String, dynamic>> people;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Team Beat Plan')),
      body: people.isEmpty
          ? const Center(child: Text('Nothing planned.', style: TextStyle(color: AppColors.muted)))
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                for (final p in people)
                  Card(
                    child: ListTile(
                      title: Text('${(p['employee'] as Map)['name']}', style: const TextStyle(fontWeight: FontWeight.w800)),
                      subtitle: Text(((p['beats'] as List?) ?? []).join(', ')),
                      trailing: Text('${p['visited']}/${p['planned']} visits',
                          style: const TextStyle(fontWeight: FontWeight.w800, color: AppColors.primary)),
                    ),
                  ),
              ],
            ),
    );
  }
}

/// Overdue by outlet or by distributor, with the employee, the days and the invoices.
class _OverdueScreen extends StatefulWidget {
  const _OverdueScreen({required this.items, required this.currency});

  final List<Map<String, dynamic>> items;
  final String? currency;

  @override
  State<_OverdueScreen> createState() => _OverdueScreenState();
}

class _OverdueScreenState extends State<_OverdueScreen> {
  String _kind = 'outlet';

  @override
  Widget build(BuildContext context) {
    final rows = widget.items.where((i) => i['kind'] == _kind).toList();
    return Scaffold(
      appBar: AppBar(title: const Text('Overdue')),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'outlet', label: Text('Outlets')),
              ButtonSegment(value: 'distributor', label: Text('Distributors')),
            ],
            selected: {_kind},
            onSelectionChanged: (v) => setState(() => _kind = v.first),
          ),
        ),
        Expanded(
          child: rows.isEmpty
              ? const Center(child: Text('Nothing overdue.', style: TextStyle(color: AppColors.muted)))
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                  children: [
                    for (final r in rows)
                      Card(
                        child: ListTile(
                          title: Text('${(r['customer'] as Map)['name']}', style: const TextStyle(fontWeight: FontWeight.w800)),
                          subtitle: Text([
                            if (r['employee'] != null) '${r['employee']}',
                            '${r['days']} days',
                            '${r['invoices']} invoice${r['invoices'] == 1 ? '' : 's'}',
                          ].join(' · ')),
                          trailing: Text(fmtMoney(r['amount'] as num?, widget.currency),
                              style: const TextStyle(fontWeight: FontWeight.w900, color: AppColors.danger)),
                        ),
                      ),
                  ],
                ),
        ),
      ]),
    );
  }
}
