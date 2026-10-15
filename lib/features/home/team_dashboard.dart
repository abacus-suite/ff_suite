import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/services.dart';
import '../../core/theme.dart';
import '../../widgets/common.dart';
import '../../widgets/skeleton.dart';
import '../team/team_live_screen.dart';
import '../team/timeline_screen.dart';
import 'manager_cards.dart';
import 'team_attendance_screen.dart';

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
  Map<String, dynamic>? _data;
  bool _loading = true;
  String? _error;
  String _period = 'today';

  static const _periods = [('today', 'Today'), ('yesterday', 'Yesterday'), ('week', 'This week'), ('month', 'This month')];

  @override
  void initState() {
    super.initState();
    Services.refresh.addListener(_quiet);
    _load();
  }

  @override
  void dispose() {
    Services.refresh.removeListener(_quiet);
    super.dispose();
  }

  void _quiet() {
    if (mounted && !_loading) _load(silent: true);
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent) setState(() => _loading = _data == null);
    try {
      final data = await Services.api.get('/api/v1/team/dashboard', query: {'period': _period}) as Map<String, dynamic>;
      if (mounted) {
        setState(() {
          _data = data;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Map<String, dynamic> get _people => (_data?['people'] as Map?)?.cast<String, dynamic>() ?? {};
  List<Map<String, dynamic>> get _members => ((_data?['members'] as List?) ?? []).cast<Map<String, dynamic>>();


  void _openMember(Map<String, dynamic> m) {
    final e = (m['employee'] as Map).cast<String, dynamic>();
    Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => TimelineScreen(employeeId: e['id'] as int, employeeName: '${e['name']}')));
  }

  /// A list of people for one figure: the drill-down behind every tile.
  void _sheet(String title, String subtitle, List<(Map<String, dynamic>, String, String?)> rows) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.78),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 19)),
                if (subtitle.isNotEmpty) Text(subtitle, style: const TextStyle(color: AppColors.muted, fontSize: 12.5)),
              ]),
            ),
            Flexible(
              child: rows.isEmpty
                  ? const Padding(padding: EdgeInsets.all(28), child: Center(child: Text('Nobody here.', style: TextStyle(color: AppColors.muted))))
                  : ListView(
                      shrinkWrap: true,
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
                      children: [
                        for (final (m, value, note) in rows)
                          ListTile(
                            onTap: () {
                              Navigator.pop(ctx);
                              _openMember(m);
                            },
                            leading: _avatar(m),
                            title: Text('${(m['employee'] as Map)['name']}', style: const TextStyle(fontWeight: FontWeight.w800)),
                            subtitle: note == null ? null : Text(note, style: const TextStyle(fontSize: 12)),
                            trailing: Text(value, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15)),
                          ),
                      ],
                    ),
            ),
          ]),
        ),
      ),
    );
  }

  Color _stateColour(String s) => switch (s) {
        'in' => AppColors.success,
        'out' => AppColors.primary,
        'leave' => AppColors.warning,
        _ => AppColors.danger,
      };

  Widget _avatar(Map<String, dynamic> m, {double size = 40}) {
    final name = '${(m['employee'] as Map)['name']}';
    final colour = _stateColour('${m['state']}');
    return SizedBox(
      width: size,
      height: size,
      child: Stack(clipBehavior: Clip.none, children: [
        CircleAvatar(
          radius: size / 2,
          backgroundColor: colour.withValues(alpha: 0.14),
          child: Text(name.isEmpty ? '?' : name[0].toUpperCase(),
              style: TextStyle(fontWeight: FontWeight.w900, color: colour, fontSize: size * 0.42)),
        ),
        Positioned(
          right: -1,
          bottom: -1,
          child: Container(
            width: size * 0.3,
            height: size * 0.3,
            decoration: BoxDecoration(color: colour, shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 2)),
          ),
        ),
      ]),
    );
  }

  // ------------------------------------------------------------------ attendance (period chips + team today)
  Widget _hero() {
    final p = _people;
    final total = (p['total'] as num?) ?? 0;
    final inNow = (p['in'] as num?) ?? 0;
    final out = (p['out'] as num?) ?? 0;
    final leave = (p['leave'] as num?) ?? 0;
    final absent = (p['absent'] as num?) ?? 0;
    final late = (p['late'] as num?) ?? 0;
    Widget tile(String label, num value, Color c, String state) => Expanded(
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => TeamAttendanceScreen(members: _members, initialTab: state))),
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
            for (final (key, label) in _periods)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  label: Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                  selected: _period == key,
                  visualDensity: VisualDensity.compact,
                  onSelected: (_) {
                    setState(() => _period = key);
                    _load();
                  },
                ),
              ),
          ]),
        ),
        const SizedBox(height: 12),
        InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => TeamAttendanceScreen(members: _members, initialTab: 'present'))),
          child: Row(children: [
            SizedBox(
              width: 96,
              height: 96,
              child: CustomPaint(
                painter: _Ring(parts: [(inNow.toDouble(), Colors.white), (out.toDouble(), const Color(0xFF9FE7F5)), (leave.toDouble(), const Color(0xFFFFD166))], total: total <= 0 ? 1 : total.toDouble()),
                child: Center(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Text('${inNow + out}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 26, height: 1)),
                    Text('of $total', style: const TextStyle(color: Colors.white, fontSize: 11)),
                  ]),
                ),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(_period == 'today' ? 'Your team today' : 'Your team', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 12.5)),
                const SizedBox(height: 3),
                Text('${inNow + out} present now', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 18)),
                const SizedBox(height: 6),
                Text('$absent absent · $leave on leave', style: const TextStyle(color: Colors.white, fontSize: 12.5)),
              ]),
            ),
            const Icon(Icons.chevron_right_rounded, color: Colors.white),
          ]),
        ),
        const SizedBox(height: 14),
        Row(children: [
          tile('Present', inNow + out, AppColors.success, 'present'),
          tile('Late', late, AppColors.warning, 'late'),
          tile('Absent', absent, AppColors.danger, 'absent'),
          tile('On Leave', leave, AppColors.primary, 'leave'),
        ]),
      ]),
    );
  }

  List<Map<String, dynamic>> _list(String key) => ((_data?[key] as List?) ?? []).cast<Map<String, dynamic>>();

  String _monthLabel() {
    const m = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];
    return m[DateTime.now().month - 1];
  }

  Widget _beatSummary() {
    final t = (_data?['totals'] as Map?)?.cast<String, dynamic>() ?? {};
    return BeatPlanSummaryCard(
      planned: (t['planned'] as num?) ?? 0,
      visited: (t['planned_done'] as num?) ?? 0,
      cancelled: (t['cancelled'] as num?) ?? 0,
      onViewAll: () => _sheet('Beat plan', _periodLabel, [
        for (final m in _members) (m, '${m['planned_done']}/${m['planned']}', '${m['visits']} visits'),
      ]),
    );
  }

  String get _periodLabel => _periods.firstWhere((p) => p.$1 == _period, orElse: () => _periods.first).$2;

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
      TeamTargetCard(targets: _list('target'), monthLabel: _monthLabel()),
      const OverdueCard(),
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

/// A ring split into coloured parts of a whole.
class _Ring extends CustomPainter {
  _Ring({required this.parts, required this.total});

  final List<(double, Color)> parts;
  final double total;

  @override
  void paint(Canvas canvas, Size size) {
    const width = 11.0;
    final rect = Rect.fromLTWH(width / 2, width / 2, size.width - width, size.height - width);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = width
      ..strokeCap = StrokeCap.round
      ..color = Colors.white.withValues(alpha: 0.22);
    canvas.drawArc(rect, 0, math.pi * 2, false, paint);
    var start = -math.pi / 2;
    for (final (value, colour) in parts) {
      if (value <= 0) continue;
      final sweep = (value / total).clamp(0.0, 1.0) * math.pi * 2;
      canvas.drawArc(rect, start, sweep, false, paint..color = colour);
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(covariant _Ring old) => old.parts != parts || old.total != total;
}
