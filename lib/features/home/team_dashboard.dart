import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../core/services.dart';
import '../../core/theme.dart';
import '../../widgets/common.dart';
import '../../widgets/skeleton.dart';
import '../team/team_live_screen.dart';
import '../team/team_beat_plan_screen.dart';
import '../team/team_target_screen.dart';
import 'manager_cards.dart';
import 'manager_home.dart' show PeopleScreen;

/// The manager's Home when "Team" is chosen: who is in, what the team has done, what needs an eye,
/// and each person to drill into.
class TeamDashboard extends StatefulWidget {
  const TeamDashboard({super.key, this.approvals});

  /// The approvals card, shown just under the attendance card.
  final Widget? approvals;

  @override
  State<TeamDashboard> createState() => _TeamDashboardState();
}

class _TeamDashboardState extends State<TeamDashboard> {
  /// Today's figures: the beat plan summary, target and alerts. They never follow the chips on the blue card.
  Map<String, dynamic>? _data;
  Map<String, dynamic>? _todayData;

  /// The team's month-to-date target and what it has achieved; null when the server has none.
  Map<String, dynamic>? _target;

  /// Today's overdue block from the team home call: it does not follow the chips either.
  Map<String, dynamic>? _overdueHome;

  /// The blue card: who was present, late, absent or on leave for the chosen period or day.
  Map<String, dynamic>? _home;
  bool _homeLoading = false;
  String? _homeError;
  bool _loading = true;
  String? _error;

  /// today | yesterday | week | month, or 'date' with [_date] set from the calendar.
  String _period = 'today';
  String? _date;

  static const _periods = [('today', 'Today'), ('yesterday', 'Yesterday'), ('week', 'This week'), ('month', 'This month')];

  @override
  void initState() {
    super.initState();
    Services.refresh.addListener(_quiet);
    _load();
    _loadHome();
  }

  @override
  void dispose() {
    Services.refresh.removeListener(_quiet);
    super.dispose();
  }

  void _quiet() {
    if (!mounted) return;
    if (!_loading) _load(silent: true);
    if (!_homeLoading) _loadHome();
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent) setState(() => _loading = _data == null);
    try {
      _target = await Services.api.get('/api/v1/team/target') as Map<String, dynamic>;
    } catch (_) {
      // No targets module: the card says so.
    }
    try {
      _overdueHome = await Services.api.get('/api/v1/team/home', query: {'period': 'today'}) as Map<String, dynamic>;
    } catch (_) {
      // No overdue block: the card stays away.
    }
    try {
      final data = await Services.api.get('/api/v1/team/dashboard', query: {'period': 'today'}) as Map<String, dynamic>;
      if (mounted) {
        setState(() {
          _data = data;
          _todayData = data;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Only the blue card reloads when a chip or the calendar is used.
  Future<void> _loadHome() async {
    final period = _period;
    final date = _date;
    setState(() {
      _homeLoading = true;
      _homeError = null;
    });
    try {
      final home = await Services.api.get('/api/v1/team/home', query: {if (date != null) 'date': date else 'period': period})
          as Map<String, dynamic>;
      if (mounted && _period == period && _date == date) setState(() => _home = home);
    } catch (e) {
      if (mounted) setState(() => _homeError = e.toString());
    } finally {
      if (mounted) setState(() => _homeLoading = false);
    }
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date == null ? DateTime.now() : DateTime.parse(_date!),
      firstDate: DateTime(2024),
      lastDate: DateTime.now(),
    );
    if (picked == null) return;
    setState(() {
      _date = fmtDate(picked);
      _period = 'date';
    });
    _loadHome();
  }

  int _count(String key) => ((((_home?['attendance'] as Map?)?[key] as Map?)?['count']) as num? ?? 0).toInt();

  // ------------------------------------------------------------------ attendance (period chips + team today)
  void _openPeople(String key) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => PeopleScreen(initial: key, period: _period, date: _date)));
  }

  Widget _hero() {
    final team = ((_home?['team_size'] as num?) ?? 0).toInt();
    final present = _count('present');
    final late = _count('late');
    final absent = _count('absent');
    final leave = _count('leave');
    final share = team == 0 ? 0.0 : (present / team).clamp(0.0, 1.0).toDouble();
    Widget tile(String label, int value, Color c, String key) => Expanded(
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: () => _openPeople(key),
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 3),
              padding: const EdgeInsets.symmetric(vertical: 11),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
              child: Column(children: [
                Text('$value', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 20, color: c)),
                Text(label, maxLines: 1, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: c)),
              ]),
            ),
          ),
        );
    Widget chip(String key, String label) {
      final on = _date == null && _period == key;
      return Padding(
        padding: const EdgeInsets.only(right: 8),
        child: ChoiceChip(
          label: Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
          selected: on,
          visualDensity: VisualDensity.compact,
          onSelected: (_) {
            setState(() {
              _period = key;
              _date = null;
            });
            _loadHome();
          },
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
            colors: [Color(0xFF1B3A7A), Color(0xFF2563EB), Color(0xFF06B6D4)], begin: Alignment.topLeft, end: Alignment.bottomRight),
        borderRadius: BorderRadius.circular(26),
        boxShadow: [BoxShadow(color: const Color(0xFF2563EB).withValues(alpha: 0.28), blurRadius: 22, offset: const Offset(0, 10))],
      ),
      child: Column(children: [
        SizedBox(
          height: 34,
          child: ListView(scrollDirection: Axis.horizontal, children: [
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: InkWell(
                onTap: _pickDate,
                borderRadius: BorderRadius.circular(18),
                child: Container(
                  width: 34,
                  decoration: BoxDecoration(
                    color: _date != null ? Colors.white : Colors.white.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.5)),
                  ),
                  child: Icon(Icons.calendar_month_rounded, size: 18, color: _date != null ? const Color(0xFF1D4ED8) : Colors.white),
                ),
              ),
            ),
            for (final (key, label) in _periods) chip(key, label),
          ]),
        ),
        const SizedBox(height: 12),
        InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: () => _openPeople('present'),
          child: Row(children: [
            SizedBox(
              width: 96,
              height: 96,
              child: Stack(alignment: Alignment.center, children: [
                SizedBox(
                  width: 96,
                  height: 96,
                  child: CircularProgressIndicator(
                      value: share, strokeWidth: 9, color: Colors.white, backgroundColor: Colors.white.withValues(alpha: 0.22)),
                ),
                Column(mainAxisSize: MainAxisSize.min, children: [
                  Text('$present', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 26, height: 1)),
                  Text('of $team', style: const TextStyle(color: Colors.white, fontSize: 11)),
                ]),
              ]),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(_period == 'today' ? 'Your team today' : (_date != null ? 'Your team on $_date' : 'Your team'),
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 12.5)),
                const SizedBox(height: 3),
                Text('$present present${_period == 'today' ? ' now' : ''}',
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 18)),
                const SizedBox(height: 6),
                Text('$absent absent · $leave on leave', style: const TextStyle(color: Colors.white, fontSize: 12.5)),
              ]),
            ),
            const Icon(Icons.chevron_right_rounded, color: Colors.white),
          ]),
        ),
        const SizedBox(height: 14),
        Row(children: [
          tile('Present', present, AppColors.success, 'present'),
          tile('Late', late, AppColors.warning, 'late'),
          tile('Absent', absent, AppColors.danger, 'absent'),
          tile('On Leave', leave, AppColors.primary, 'leave'),
        ]),
        if (_homeLoading) const Padding(padding: EdgeInsets.only(top: 10), child: LinearProgressIndicator(minHeight: 2)),
        if (_homeError != null && _home == null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(_homeError!, style: const TextStyle(color: Colors.white, fontSize: 12)),
          ),
      ]),
    );
  }

  List<Map<String, dynamic>> _list(String key) => (((_todayData ?? _data)?[key] as List?) ?? []).cast<Map<String, dynamic>>();

  String _monthLabel() {
    const m = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];
    return m[DateTime.now().month - 1];
  }

  Widget _beatSummary() {
    final today = _todayData ?? _data;
    final t = (today?['totals'] as Map?)?.cast<String, dynamic>() ?? {};
    return BeatPlanSummaryCard(
      planned: (t['planned'] as num?) ?? 0,
      visited: (t['planned_done'] as num?) ?? 0,
      cancelled: (t['cancelled'] as num?) ?? 0,
      onViewAll: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const TeamBeatPlanScreen())),
    );
  }

  // ------------------------------------------------------------------ shortcuts
  Widget _shortcuts() {
    Widget tile(IconData icon, String label, Color c, VoidCallback onTap) => Expanded(
          child: InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: onTap,
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 4),
              padding: const EdgeInsets.symmetric(vertical: 14),
              decoration: BoxDecoration(color: c.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(18)),
              child: Column(children: [
                Icon(icon, color: c),
                const SizedBox(height: 6),
                Text(label, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12)),
              ]),
            ),
          ),
        );
    return Row(children: [
      tile(Icons.map_rounded, 'Live map', AppColors.success, () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const TeamLiveScreen()))),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Padding(padding: EdgeInsets.all(40), child: LoadingView());
    if (_error != null && _data == null) {
      return Card(child: ErrorView(message: _error!, onRetry: _load));
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _hero(),
      const SizedBox(height: 12),
      if (widget.approvals != null) ...[
        widget.approvals!,
        const SizedBox(height: 12),
      ],
      _beatSummary(),
      TeamTargetCard(
        monthLabel: _monthLabel(),
        data: _target,
        onTap: _target == null ? null : () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const TeamTargetScreen())),
      ),
      OverdueCard(block: (_overdueHome?['overdue'] as Map?)?.cast<String, dynamic>(), currency: _overdueHome?['currency'] as String?),
      const AssignedTasksCard(),
      WorkAlertsCard(alerts: _list('work_alerts')),
      _shortcuts(),
      // The bar at the bottom floats over the page: leave its height free.
      SizedBox(height: 40 + MediaQuery.of(context).padding.bottom),
    ]);
  }
}

String fmtCompact(num v) {
  final n = v.toDouble();
  if (n >= 10000000) return '${(n / 10000000).toStringAsFixed(1)}Cr';
  if (n >= 100000) return '${(n / 100000).toStringAsFixed(1)}L';
  if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}k';
  return n.toStringAsFixed(0);
}
