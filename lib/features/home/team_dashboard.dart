import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../core/services.dart';
import '../../core/theme.dart';
import '../../widgets/common.dart';
import '../../widgets/skeleton.dart';
import '../team/team_collections_screen.dart';
import '../team/team_live_screen.dart';
import '../team/team_tree_screen.dart';
import '../team/timeline_screen.dart';

/// The manager's Home when "Team" is chosen: who is in, what the team has done, what needs an eye,
/// and each person to drill into.
class TeamDashboard extends StatefulWidget {
  const TeamDashboard({super.key});

  @override
  State<TeamDashboard> createState() => _TeamDashboardState();
}

class _TeamDashboardState extends State<TeamDashboard> {
  Map<String, dynamic>? _data;
  bool _loading = true;
  String? _error;
  String _period = 'today';
  String _sort = 'order_amount';
  bool _all = false;
  Map<String, dynamic>? _hold;

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
      Map<String, dynamic>? hold;
      try {
        hold = await Services.api.get('/api/v1/team/collections') as Map<String, dynamic>;
      } catch (_) {
        // an older server has no collections view
      }
      if (mounted) {
        setState(() {
          _hold = hold;
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
  Map<String, dynamic> get _totals => (_data?['totals'] as Map?)?.cast<String, dynamic>() ?? {};
  Map<String, dynamic> get _alerts => (_data?['alerts'] as Map?)?.cast<String, dynamic>() ?? {};
  List<Map<String, dynamic>> get _members => ((_data?['members'] as List?) ?? []).cast<Map<String, dynamic>>();
  String? get _currency => _data?['currency'] as String?;

  String _money(num? v) => fmtMoney(v, _currency);

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

  String _stateLabel(String s) => switch (s) {
        'in' => 'Checked in',
        'out' => 'Checked out',
        'leave' => 'On leave',
        _ => 'Not in',
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

  // ------------------------------------------------------------------ hero
  Widget _hero() {
    final p = _people;
    final total = (p['total'] as num?) ?? 0;
    final inNow = (p['in'] as num?) ?? 0;
    final out = (p['out'] as num?) ?? 0;
    final leave = (p['leave'] as num?) ?? 0;
    final absent = (p['absent'] as num?) ?? 0;
    final t = _totals;
    final planned = (t['planned'] as num?) ?? 0;
    final done = (t['planned_done'] as num?) ?? 0;
    Widget tile(IconData icon, String value, String label, VoidCallback onTap) => Expanded(
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: onTap,
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 3),
              padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 6),
              decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(16)),
              child: Column(children: [
                Icon(icon, color: Colors.white, size: 17),
                const SizedBox(height: 5),
                FittedBox(
                    child: Text(value, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 16))),
                const SizedBox(height: 1),
                Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 10.5)),
              ]),
            ),
          ),
        );
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
            colors: [Color(0xFF1B3A7A), Color(0xFF2563EB), Color(0xFF06B6D4)], begin: Alignment.topLeft, end: Alignment.bottomRight),
        borderRadius: BorderRadius.circular(26),
        boxShadow: [BoxShadow(color: const Color(0xFF2563EB).withValues(alpha: 0.28), blurRadius: 22, offset: const Offset(0, 10))],
      ),
      child: Column(children: [
        InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: () => _sheet('Team today', '${_members.length} people', [
            for (final m in _members) (m, _stateLabel('${m['state']}'), m['at_client'] != null ? 'At ${(m['at_client'] as Map)['name']}' : null),
          ]),
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
                Text('$inNow working now', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 18)),
                const SizedBox(height: 6),
                Text('$absent not in · $leave on leave${(_people['late'] as num? ?? 0) > 0 ? ' · ${_people['late']} late' : ''}',
                    style: const TextStyle(color: Colors.white, fontSize: 12.5)),
              ]),
            ),
            const Icon(Icons.chevron_right_rounded, color: Colors.white),
          ]),
        ),
        const SizedBox(height: 14),
        Row(children: [
          tile(Icons.storefront_rounded, '$done/$planned', 'Visits planned', () => _breakdown('visits')),
          tile(Icons.shopping_bag_rounded, _money(t['order_amount'] as num?), '${t['orders'] ?? 0} orders', () => _breakdown('order_amount')),
          tile(Icons.payments_rounded, _money(t['collections'] as num?), 'Collected', () => _breakdown('collections')),
          tile(Icons.route_rounded, '${((t['km'] as num?) ?? 0).toStringAsFixed(0)} km', 'Travelled', () => _breakdown('km')),
        ]),
      ]),
    );
  }

  /// People ranked by one figure.
  void _breakdown(String key) {
    final title = switch (key) {
      'visits' => 'Visits',
      'order_amount' => 'Orders and demands',
      'collections' => 'Collections',
      _ => 'Distance travelled',
    };
    final sorted = [..._members]..sort((a, b) => ((b[key] as num?) ?? 0).compareTo((a[key] as num?) ?? 0));
    _sheet(title, _periodLabel, [
      for (final m in sorted)
        (
          m,
          switch (key) {
            'visits' => '${m['visits']}',
            'order_amount' => _money(m['order_amount'] as num?),
            'collections' => _money(m['collections'] as num?),
            _ => '${((m['km'] as num?) ?? 0).toStringAsFixed(1)} km',
          },
          switch (key) {
            'visits' => '${m['planned_done']} of ${m['planned']} planned · ${m['productive']} productive',
            'order_amount' => '${m['orders']} orders',
            _ => null,
          },
        ),
    ]);
  }

  String get _periodLabel => _periods.firstWhere((p) => p.$1 == _period, orElse: () => _periods.first).$2;

  // ------------------------------------------------------------------ attendance
  Widget _attendance() {
    final p = _people;
    Widget chip(String label, num value, Color c, String state) => Expanded(
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: () => _sheet(label, '', [
              for (final m in _members)
                if (state == 'late' ? (m['late_minutes'] as num? ?? 0) > 0 : m['state'] == state)
                  (m, state == 'late' ? '${m['late_minutes']} min late' : _stateLabel('${m['state']}'),
                      m['at_client'] != null ? 'At ${(m['at_client'] as Map)['name']}' : null),
            ]),
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 3),
              padding: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(color: c.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(16)),
              child: Column(children: [
                Text('$value', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 21, color: c)),
                Text(label, maxLines: 1, style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600)),
              ]),
            ),
          ),
        );
    return _card(
      'Attendance',
      Icons.how_to_reg_rounded,
      Row(children: [
        chip('Working', (p['in'] as num?) ?? 0, AppColors.success, 'in'),
        chip('Done', (p['out'] as num?) ?? 0, AppColors.primary, 'out'),
        chip('Not in', (p['absent'] as num?) ?? 0, AppColors.danger, 'absent'),
        chip('Leave', (p['leave'] as num?) ?? 0, AppColors.warning, 'leave'),
        chip('Late', (p['late'] as num?) ?? 0, AppColors.purple, 'late'),
      ]),
    );
  }

  // ------------------------------------------------------------------ collections in hand
  Widget _holding() {
    final h = _hold;
    if (h == null) return const SizedBox.shrink();
    final totals = (h['totals'] as Map?)?.cast<String, dynamic>() ?? {};
    Widget part(String label, num? v, Color c, IconData icon) => Expanded(
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 3),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: c.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(16)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(icon, size: 17, color: c),
              const SizedBox(height: 4),
              FittedBox(child: Text(fmtMoney(v, h['currency'] as String?), style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: Color(0xFF0F172A)))),
              Text(label, style: const TextStyle(fontSize: 11.5, color: Color(0xFF334155), fontWeight: FontWeight.w600)),
            ]),
          ),
        );
    return InkWell(
      borderRadius: BorderRadius.circular(22),
      onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const TeamCollectionsScreen())),
      child: _card(
        'Collections in hand',
        Icons.account_balance_wallet_rounded,
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(
              child: Text(fmtMoney(totals['total'] as num?, h['currency'] as String?),
                  style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 24, color: Color(0xFF0F172A))),
            ),
            const Text('By person, distributor, outlet', style: TextStyle(fontSize: 11.5, color: Color(0xFF334155))),
            const Icon(Icons.chevron_right_rounded, color: Color(0xFF334155)),
          ]),
          const SizedBox(height: 10),
          Row(children: [
            part('For the office', totals['office'] as num?, AppColors.primary, Icons.apartment_rounded),
            part('For distributors', totals['distributors'] as num?, AppColors.warning, Icons.local_shipping_rounded),
          ]),
        ]),
      ),
    );
  }

  // ------------------------------------------------------------------ alerts
  Widget _alertsCard() {
    final a = _alerts;
    final items = <(String, num, IconData, bool Function(Map<String, dynamic>))>[
      ('No signal', (a['no_signal'] as num?) ?? 0, Icons.signal_wifi_off_rounded, (m) => m['no_signal'] == true),
      ('Low battery', (a['low_battery'] as num?) ?? 0, Icons.battery_alert_rounded, (m) => m['low_battery'] == true),
      ('GPS off', (a['gps_off'] as num?) ?? 0, Icons.location_off_rounded, (m) => m['gps_off'] == true),
      ('Not moving', (a['inactive'] as num?) ?? 0, Icons.hourglass_bottom_rounded, (m) => m['inactive'] == true),
    ].where((i) => i.$2 > 0).toList();
    if (items.isEmpty || _period != 'today') return const SizedBox.shrink();
    return _card(
      'Needs a look',
      Icons.notifications_active_rounded,
      Wrap(spacing: 8, runSpacing: 8, children: [
        for (final (label, count, icon, test) in items)
          ActionChip(
            avatar: Icon(icon, size: 16, color: AppColors.danger),
            label: Text('$label · $count', style: const TextStyle(fontWeight: FontWeight.w700)),
            onPressed: () => _sheet(label, 'Checked-in people with this problem', [
              for (final m in _members)
                if (test(m)) (m, m['battery'] != null ? '${m['battery']}%' : '', null),
            ]),
          ),
      ]),
    );
  }

  // ------------------------------------------------------------------ performance
  Widget _performance() {
    final sorted = [..._members]..sort((a, b) => ((b[_sort] as num?) ?? 0).compareTo((a[_sort] as num?) ?? 0));
    final shown = _all ? sorted : sorted.take(6).toList();
    String value(Map<String, dynamic> m) => switch (_sort) {
          'visits' => '${m['visits']}',
          'collections' => _money(m['collections'] as num?),
          'km' => '${((m['km'] as num?) ?? 0).toStringAsFixed(1)} km',
          _ => _money(m['order_amount'] as num?),
        };
    final peak = sorted.isEmpty ? 0.0 : ((sorted.first[_sort] as num?) ?? 0).toDouble();
    return _card(
      'Team performance',
      Icons.leaderboard_rounded,
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(
          height: 38,
          child: ListView(scrollDirection: Axis.horizontal, children: [
            for (final (key, label) in const [('order_amount', 'Orders'), ('visits', 'Visits'), ('collections', 'Collections'), ('km', 'Distance')])
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(label: Text(label), selected: _sort == key, onSelected: (_) => setState(() => _sort = key)),
              ),
          ]),
        ),
        const SizedBox(height: 6),
        for (final (i, m) in shown.indexed)
          InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: () => _openMember(m),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 2),
              child: Row(children: [
                SizedBox(width: 22, child: Text('${i + 1}', style: const TextStyle(fontWeight: FontWeight.w900, color: AppColors.muted))),
                _avatar(m, size: 38),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('${(m['employee'] as Map)['name']}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800)),
                    const SizedBox(height: 3),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: peak <= 0 ? 0 : (((m[_sort] as num?) ?? 0) / peak).clamp(0.0, 1.0).toDouble(),
                        minHeight: 5,
                        backgroundColor: AppColors.border,
                        color: AppColors.primary,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                        '${m['planned_done']}/${m['planned']} planned · ${m['visits']} visits'
                        '${m['at_client'] != null ? ' · at ${(m['at_client'] as Map)['name']}' : ''}',
                        maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11.5, color: AppColors.muted)),
                  ]),
                ),
                const SizedBox(width: 8),
                Text(value(m), style: const TextStyle(fontWeight: FontWeight.w900)),
                const Icon(Icons.chevron_right_rounded, color: AppColors.muted, size: 20),
              ]),
            ),
          ),
        if (sorted.length > 6)
          Center(
            child: TextButton(onPressed: () => setState(() => _all = !_all), child: Text(_all ? 'Show less' : 'Show all ${sorted.length}')),
          ),
        if (sorted.isEmpty) const Padding(padding: EdgeInsets.all(16), child: Text('No team members.', style: TextStyle(color: AppColors.muted))),
      ]),
    );
  }

  // ------------------------------------------------------------------ trend
  Widget _trend() {
    final days = ((_data?['trend'] as List?) ?? []).cast<Map<String, dynamic>>();
    final peak = days.fold<double>(1, (a, d) => math.max(a, ((d['amount'] as num?) ?? 0).toDouble()));
    return _card(
      'Last 7 days',
      Icons.show_chart_rounded,
      Column(children: [
        SizedBox(
          height: 130,
          child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            for (final d in days)
              Expanded(
                child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
                  Text(((d['amount'] as num?) ?? 0) > 0 ? fmtCompact(d['amount'] as num) : '',
                      style: const TextStyle(fontSize: 9.5, color: AppColors.muted)),
                  const SizedBox(height: 3),
                  Container(
                    height: math.max(4, 84 * (((d['amount'] as num?) ?? 0).toDouble() / peak)),
                    margin: const EdgeInsets.symmetric(horizontal: 6),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(colors: [Color(0xFF2563EB), Color(0xFF06B6D4)], begin: Alignment.bottomCenter, end: Alignment.topCenter),
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text('${d['label']}', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
                  Text('${d['visits']}v', style: const TextStyle(fontSize: 10, color: AppColors.muted)),
                ]),
              ),
          ]),
        ),
        const SizedBox(height: 4),
        const Align(
            alignment: Alignment.centerRight,
            child: Text('bars: orders · v: visits', style: TextStyle(fontSize: 10.5, color: AppColors.muted))),
      ]),
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
      tile(Icons.account_tree_rounded, 'Team tree', AppColors.purple, () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const TeamTreeScreen()))),
    ]);
  }

  Widget _card(String title, IconData icon, Widget child) => Container(
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
            Text(title, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15.5)),
          ]),
          const SizedBox(height: 12),
          child,
        ]),
      );

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Padding(padding: EdgeInsets.all(40), child: LoadingView());
    if (_error != null && _data == null) {
      return Card(child: ErrorView(message: _error!, onRetry: _load));
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SizedBox(
        height: 40,
        child: ListView(scrollDirection: Axis.horizontal, children: [
          for (final (key, label) in _periods)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                label: Text(label),
                selected: _period == key,
                onSelected: (_) {
                  setState(() => _period = key);
                  _load();
                },
              ),
            ),
        ]),
      ),
      const SizedBox(height: 10),
      _hero(),
      const SizedBox(height: 12),
      _attendance(),
      _holding(),
      _alertsCard(),
      _performance(),
      _trend(),
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
