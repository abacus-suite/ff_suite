import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../../core/format.dart';
import '../../core/services.dart';
import '../../core/theme.dart';
import '../../widgets/common.dart';
import '../../widgets/skeleton.dart';
import 'team_leaves.dart';

const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

String _short(DateTime d) => '${d.day} ${_months[d.month - 1]}';

DateTime? _day(dynamic iso) => iso is String && iso.length >= 10 ? DateTime.tryParse(iso.substring(0, 10)) : null;

/// "12 Oct", or "12 Oct to 14 Oct" for a stretch.
String _range(dynamic from, dynamic to) {
  final a = _day(from), b = _day(to);
  if (a == null) return '';
  if (b == null || (a.year == b.year && a.month == b.month && a.day == b.day)) return _short(a);
  return '${_short(a)} to ${_short(b)}';
}

Color _stateColour(String state) => switch (state) {
      'validate' => AppColors.success,
      'refuse' => AppColors.danger,
      'cancel' => AppColors.muted,
      _ => AppColors.warning,
    };

/// My time off: what is left of each type, what is coming up, what I asked for and where it stands.
class LeavesScreen extends StatefulWidget {
  const LeavesScreen({super.key});

  @override
  State<LeavesScreen> createState() => _LeavesScreenState();
}

class _LeavesScreenState extends State<LeavesScreen> {
  Map<String, dynamic>? _data;
  bool _loading = true;
  String? _error;
  String _filter = 'all';
  String _tab = 'requests';

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
    if (!mounted) return;
    setState(() => _error = null);
    try {
      final data = await Services.api.get('/api/v1/leaves') as Map<String, dynamic>;
      if (!mounted) return;
      setState(() {
        _data = data;
        _loading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  List<Map<String, dynamic>> _list(String key) => ((_data?[key] as List?) ?? []).cast<Map<String, dynamic>>();

  Future<void> _request({Map<String, dynamic>? type, Map<String, dynamic>? again}) async {
    final types = _list('types');
    if (types.isEmpty) {
      showSnack(context, 'No leave types are set up yet.');
      return;
    }
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => LeaveRequestScreen(types: types, initial: type, copyOf: again)),
    );
    if (saved == true) await _load();
  }

  Future<void> _withdraw(Map<String, dynamic> leave) async {
    final sure = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Withdraw this request?'),
        content: Text('${(leave['type'] as Map)['name']} · ${_range(leave['from'], leave['to'])}'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Keep it')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Withdraw')),
        ],
      ),
    );
    if (sure != true) return;
    try {
      await Services.outbox.submit('/api/v1/leaves/${leave['id']}', {'uuid': const Uuid().v4()});
      if (mounted) showSnack(context, 'Request withdrawn');
      await _load();
    } catch (e) {
      if (mounted) showProblem(context, e.toString());
    }
  }

  /// The soonest approved (or waiting) leave that has not started, for the banner.
  Map<String, dynamic>? get _next {
    final today = DateTime.now();
    final start = DateTime(today.year, today.month, today.day);
    Map<String, dynamic>? best;
    DateTime? bestDate;
    for (final l in _list('leaves')) {
      if (l['state'] == 'refuse' || l['state'] == 'cancel') continue;
      final to = _day(l['to']);
      final from = _day(l['from']);
      if (from == null || to == null || to.isBefore(start)) continue;
      if (bestDate == null || from.isBefore(bestDate)) {
        best = l;
        bestDate = from;
      }
    }
    return best;
  }

  @override
  Widget build(BuildContext context) {
    final data = _data;
    final summary = (data?['summary'] as Map?)?.cast<String, dynamic>() ?? {};
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('My Time Off'),
        actions: [
          IconButton(
            tooltip: 'Calendar',
            icon: const Icon(Icons.calendar_month_rounded),
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const LeaveCalendarScreen())),
          ),
          if (Services.auth.profile?.isManager ?? false)
            IconButton(
              tooltip: 'Team time off',
              icon: const Icon(Icons.groups_rounded),
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const TeamLeavesScreen())),
            ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _request(),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Request'),
      ),
      body: _loading
          ? const LoadingView()
          : _error != null && data == null
              ? ErrorView(message: _error!, onRetry: _load)
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 110),
                    children: [
                      _hero(summary),
                      if (_next != null) ...[const SizedBox(height: 12), _nextBanner(_next!)],
                      if (_list('types').isNotEmpty) ...[
                        const SizedBox(height: 18),
                        _heading('Your balance', 'Tap a type to ask for it'),
                        const SizedBox(height: 8),
                        SizedBox(
                          height: 142,
                          child: ListView(
                            scrollDirection: Axis.horizontal,
                            clipBehavior: Clip.none,
                            children: [for (final (i, t) in _list('types').indexed) _typeCard(t, i)],
                          ),
                        ),
                      ],
                      if (_list('holidays').isNotEmpty) ...[
                        const SizedBox(height: 18),
                        _heading('Coming holidays', 'Days the company is off'),
                        const SizedBox(height: 8),
                        SizedBox(
                          height: 74,
                          child: ListView(
                            scrollDirection: Axis.horizontal,
                            clipBehavior: Clip.none,
                            children: [for (final h in _list('holidays')) _holiday(h)],
                          ),
                        ),
                      ],
                      const SizedBox(height: 18),
                      SegmentedButton<String>(
                        showSelectedIcon: false,
                        segments: [
                          ButtonSegment(value: 'requests', label: Text('Requests (${_list('leaves').length})')),
                          ButtonSegment(value: 'allocations', label: Text('Allocations (${_list('allocations').length})')),
                        ],
                        selected: {_tab},
                        onSelectionChanged: (v) => setState(() => _tab = v.first),
                      ),
                      const SizedBox(height: 12),
                      if (_tab == 'requests') ..._requests() else ..._allocations(),
                    ],
                  ),
                ),
    );
  }

  Widget _heading(String title, String sub) => Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
        Text(title, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 17)),
        const SizedBox(width: 8),
        Expanded(child: Text(sub, style: const TextStyle(fontSize: 12, color: AppColors.muted))),
      ]);

  // ------------------------------------------------------------------ hero
  Widget _hero(Map<String, dynamic> s) {
    final allocated = ((s['allocated'] as num?) ?? 0).toDouble();
    final used = ((s['used'] as num?) ?? 0).toDouble();
    final pending = ((s['pending'] as num?) ?? 0).toDouble();
    final remaining = ((s['remaining'] as num?) ?? 0).toDouble();
    Widget stat(String label, double v) => Expanded(
          child: Column(children: [
            Text(fmtQty(v), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 19)),
            const SizedBox(height: 2),
            Text(label, style: const TextStyle(color: Colors.white70, fontSize: 11.5, fontWeight: FontWeight.w600)),
          ]),
        );
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 14),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
            colors: [Color(0xFF1B3A7A), Color(0xFF2563EB), Color(0xFF06B6D4)], begin: Alignment.topLeft, end: Alignment.bottomRight),
        borderRadius: BorderRadius.circular(26),
        boxShadow: [BoxShadow(color: const Color(0xFF2563EB).withValues(alpha: 0.3), blurRadius: 22, offset: const Offset(0, 10))],
      ),
      child: Column(children: [
        Row(children: [
          SizedBox(
            width: 112,
            height: 112,
            child: CustomPaint(
              painter: _RingPainter(
                parts: [(used, Colors.white), (pending, const Color(0xFFFFD166))],
                total: allocated <= 0 ? 1 : allocated,
                track: Colors.white.withValues(alpha: 0.22),
                width: 13,
              ),
              child: Center(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Text(fmtQty(remaining),
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 28, height: 1)),
                  const Text('days left', style: TextStyle(color: Colors.white70, fontSize: 11)),
                ]),
              ),
            ),
          ),
          const SizedBox(width: 18),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('This year', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.w700, fontSize: 12.5)),
              const SizedBox(height: 4),
              Text(allocated > 0 ? '${fmtQty(used)} of ${fmtQty(allocated)} days used' : 'No allocated days',
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 16)),
              const SizedBox(height: 10),
              Wrap(spacing: 8, runSpacing: 6, children: [
                _legendDot(Colors.white, 'Used'),
                _legendDot(const Color(0xFFFFD166), 'Waiting'),
              ]),
            ]),
          ),
        ]),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(16)),
          child: Row(children: [
            stat('Allocated', allocated),
            stat('Used', used),
            stat('Waiting', pending),
            stat('Available', remaining),
          ]),
        ),
      ]),
    );
  }

  Widget _legendDot(Color c, String label) => Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 9, height: 9, decoration: BoxDecoration(color: c, shape: BoxShape.circle)),
        const SizedBox(width: 5),
        Text(label, style: const TextStyle(color: Colors.white70, fontSize: 12)),
      ]);

  Widget _nextBanner(Map<String, dynamic> l) {
    final from = _day(l['from']);
    final now = DateTime.now();
    final days = from == null ? 0 : from.difference(DateTime(now.year, now.month, now.day)).inDays;
    final on = days <= 0;
    final approved = l['state'] == 'validate';
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: (approved ? AppColors.success : AppColors.warning).withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: (approved ? AppColors.success : AppColors.warning).withValues(alpha: 0.3)),
      ),
      child: Row(children: [
        Icon(Icons.beach_access_rounded, color: approved ? AppColors.success : AppColors.warning),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(on ? 'You are on leave now' : 'Next leave in $days day${days == 1 ? '' : 's'}',
                style: const TextStyle(fontWeight: FontWeight.w900)),
            Text(
                '${(l['type'] as Map)['name']} · ${_range(l['from'], l['to'])}'
                '${approved ? '' : ' · waiting for approval'}',
                style: const TextStyle(fontSize: 12.5, color: AppColors.muted)),
          ]),
        ),
      ]),
    );
  }

  // ------------------------------------------------------------------ balance cards
  Widget _typeCard(Map<String, dynamic> t, int index) {
    const palette = [AppColors.primary, AppColors.purple, AppColors.success, AppColors.warning, AppColors.sky, AppColors.teal];
    final colour = palette[index % palette.length];
    final limited = t['requires_allocation'] == true;
    final allocated = ((t['allocated'] as num?) ?? 0).toDouble();
    final used = ((t['used'] as num?) ?? 0).toDouble();
    final pending = ((t['pending'] as num?) ?? 0).toDouble();
    final remaining = ((t['remaining'] as num?) ?? 0).toDouble();
    final canAsk = t['can_request'] != false;
    return GestureDetector(
      onTap: canAsk ? () => _request(type: t) : () => showSnack(context, 'Nothing left to request for ${t['name']}.'),
      child: Container(
        width: 156,
        margin: const EdgeInsets.only(right: 12),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(22),
          boxShadow: [BoxShadow(color: colour.withValues(alpha: 0.14), blurRadius: 14, offset: const Offset(0, 6))],
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            SizedBox(
              width: 46,
              height: 46,
              child: CustomPaint(
                painter: _RingPainter(
                  parts: limited ? [(used, colour), (pending, AppColors.warning)] : [(1, colour)],
                  total: limited ? (allocated <= 0 ? 1 : allocated) : 1,
                  track: colour.withValues(alpha: 0.15),
                  width: 6,
                ),
                child: Center(
                  child: Icon(limited ? Icons.event_available_rounded : Icons.all_inclusive_rounded, size: 17, color: colour),
                ),
              ),
            ),
            const Spacer(),
            if (canAsk) Icon(Icons.add_circle_rounded, color: colour, size: 24),
          ]),
          const Spacer(),
          Text('${t['name']}',
              maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14)),
          const SizedBox(height: 2),
          Text(limited ? '${fmtQty(remaining)} left of ${fmtQty(allocated)}' : 'No limit',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: limited && remaining <= 0 ? AppColors.danger : AppColors.muted)),
          if (pending > 0) Text('${fmtQty(pending)} waiting', style: const TextStyle(fontSize: 11, color: AppColors.warning)),
        ]),
      ),
    );
  }

  Widget _holiday(Map<String, dynamic> h) {
    final d = _day(h['date']);
    return Container(
      width: 170,
      margin: const EdgeInsets.only(right: 10),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18)),
      child: Row(children: [
        Container(
          width: 46,
          decoration: BoxDecoration(color: AppColors.danger.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12)),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Text(d == null ? '' : '${d.day}', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18, color: AppColors.danger)),
            Text(d == null ? '' : _months[d.month - 1], style: const TextStyle(fontSize: 10.5, color: AppColors.danger)),
          ]),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text('${h['name']}', maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5)),
        ),
      ]),
    );
  }

  // ------------------------------------------------------------------ requests
  List<Widget> _requests() {
    final leaves = _list('leaves');
    final shown = _filter == 'all'
        ? leaves
        : leaves
            .where((l) => _filter == 'waiting' ? const ['confirm', 'validate1', 'draft'].contains(l['state']) : l['state'] == _filter)
            .toList();
    int count(String f) => f == 'all'
        ? leaves.length
        : leaves.where((l) => f == 'waiting' ? const ['confirm', 'validate1', 'draft'].contains(l['state']) : l['state'] == f).length;
    return [
      SizedBox(
        height: 40,
        child: ListView(scrollDirection: Axis.horizontal, children: [
          for (final (key, label) in const [('all', 'All'), ('waiting', 'Waiting'), ('validate', 'Approved'), ('refuse', 'Refused')])
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                label: Text('$label ${count(key)}'),
                selected: _filter == key,
                onSelected: (_) => setState(() => _filter = key),
              ),
            ),
        ]),
      ),
      const SizedBox(height: 8),
      for (final l in shown) _leaveCard(l),
      if (shown.isEmpty)
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 28),
          child: Center(child: Text('No requests here.', style: TextStyle(color: AppColors.muted))),
        ),
    ];
  }

  Widget _leaveCard(Map<String, dynamic> leave) {
    final state = '${leave['state']}';
    final colour = _stateColour(state);
    final approval = (leave['approval'] as Map?)?.cast<String, dynamic>();
    final steps = ((approval?['steps'] as List?) ?? []).cast<Map<String, dynamic>>();
    final half = leave['half_day'] == true;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: const Color(0xFF1B3A7A).withValues(alpha: 0.06), blurRadius: 12, offset: const Offset(0, 4))],
      ),
      clipBehavior: Clip.antiAlias,
      child: IntrinsicHeight(
        child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Container(width: 6, color: colour),
          Expanded(
            child: Theme(
              data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                tilePadding: const EdgeInsets.fromLTRB(14, 6, 12, 6),
                childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
                shape: const RoundedRectangleBorder(),
                collapsedShape: const RoundedRectangleBorder(),
                title: Text('${(leave['type'] as Map)['name']}', style: const TextStyle(fontWeight: FontWeight.w900)),
                subtitle: Padding(
                  padding: const EdgeInsets.only(top: 3),
                  child: Row(children: [
                    const Icon(Icons.event_rounded, size: 14, color: AppColors.muted),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(
                          '${_range(leave['from'], leave['to'])}'
                          '${half ? ' · half day${leave['half_day_period'] != null ? ' (${leave['half_day_period'] == 'pm' ? 'afternoon' : 'morning'})' : ''}' : ''}',
                          style: const TextStyle(fontSize: 12.5)),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(color: AppColors.primary.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)),
                      child: Text('${fmtQty(leave['days'] as num? ?? 0)} d',
                          style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, color: AppColors.primary)),
                    ),
                  ]),
                ),
                trailing: StatusBadge(state, label: '${leave['state_label']}'),
                children: [
                  if (asText(leave['reason']) != null)
                    Align(alignment: Alignment.centerLeft, child: Text('Reason: ${leave['reason']}', style: const TextStyle(fontSize: 13))),
                  if (leave['requested_on'] != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Align(
                          alignment: Alignment.centerLeft,
                          child: Text('Asked on ${fmtTime(leave['requested_on'])}, ${_range(leave['requested_on'], null)}',
                              style: const TextStyle(fontSize: 12, color: AppColors.muted))),
                    ),
                  if (steps.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    for (final (i, step) in steps.indexed) _step(step, i == steps.length - 1),
                  ],
                  const SizedBox(height: 6),
                  Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                    TextButton.icon(
                      onPressed: () => _request(again: leave),
                      icon: const Icon(Icons.copy_rounded, size: 17),
                      label: const Text('Ask again'),
                    ),
                    if (leave['can_cancel'] == true)
                      TextButton.icon(
                        onPressed: () => _withdraw(leave),
                        icon: const Icon(Icons.undo_rounded, size: 17),
                        label: const Text('Withdraw'),
                      ),
                  ]),
                ],
              ),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _step(Map<String, dynamic> step, bool last) {
    final s = '${step['state']}';
    final colour = s == 'done' ? AppColors.success : (s == 'rejected' ? AppColors.danger : AppColors.muted);
    return IntrinsicHeight(
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Column(children: [
          Container(
            width: 22,
            height: 22,
            decoration: BoxDecoration(shape: BoxShape.circle, color: s == 'done' || s == 'rejected' ? colour : Colors.white, border: Border.all(color: colour, width: 2)),
            child: Icon(s == 'rejected' ? Icons.close_rounded : Icons.check_rounded, size: 13, color: s == 'done' || s == 'rejected' ? Colors.white : Colors.transparent),
          ),
          if (!last) Expanded(child: Container(width: 2, color: AppColors.border)),
        ]),
        const SizedBox(width: 10),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${step['name']}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
              Text(
                  '${asText(step['approver']) ?? ''} · ${s == 'done' ? 'approved' : s == 'rejected' ? 'refused' : 'waiting'}',
                  style: TextStyle(fontSize: 12, color: colour)),
            ]),
          ),
        ),
      ]),
    );
  }

  // ------------------------------------------------------------------ allocations
  List<Widget> _allocations() {
    final rows = _list('allocations');
    if (rows.isEmpty) {
      return const [Padding(padding: EdgeInsets.symmetric(vertical: 28), child: Center(child: Text('No allocations yet.', style: TextStyle(color: AppColors.muted))))];
    }
    return [
      for (final a in rows)
        Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
          child: Row(children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(color: AppColors.primary.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(14)),
              child: const Icon(Icons.card_giftcard_rounded, color: AppColors.primary),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${(a['type'] as Map)['name']}', style: const TextStyle(fontWeight: FontWeight.w900)),
                Text(
                    [
                      if (a['from'] != null) 'From ${_range(a['from'], null)}',
                      a['to'] != null ? 'to ${_range(a['to'], null)}' : 'no end date',
                      if (asText(a['name']) != null) '${a['name']}',
                    ].join(' · '),
                    style: const TextStyle(fontSize: 12, color: AppColors.muted)),
              ]),
            ),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text('${fmtQty(a['days'] as num? ?? 0)} days', style: const TextStyle(fontWeight: FontWeight.w900)),
              if (a['used'] != null) Text('${fmtQty(a['used'] as num)} used', style: const TextStyle(fontSize: 11.5, color: AppColors.muted)),
            ]),
          ]),
        ),
    ];
  }
}

/// A ring split into coloured parts of a whole.
class _RingPainter extends CustomPainter {
  _RingPainter({required this.parts, required this.total, required this.track, required this.width});

  final List<(double, Color)> parts;
  final double total;
  final Color track;
  final double width;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromLTWH(width / 2, width / 2, size.width - width, size.height - width);
    final base = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = width
      ..strokeCap = StrokeCap.round
      ..color = track;
    canvas.drawArc(rect, 0, math.pi * 2, false, base);
    var start = -math.pi / 2;
    for (final (value, colour) in parts) {
      if (value <= 0) continue;
      final sweep = (value / total).clamp(0.0, 1.0) * math.pi * 2;
      canvas.drawArc(rect, start, sweep, false, base..color = colour);
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(covariant _RingPainter old) => old.parts != parts || old.total != total;
}

/// Ask for time off: a type, a stretch of days, and why.
class LeaveRequestScreen extends StatefulWidget {
  const LeaveRequestScreen({super.key, required this.types, this.initial, this.copyOf});

  final List<Map<String, dynamic>> types;

  /// A type to start on, from tapping its balance card.
  final Map<String, dynamic>? initial;

  /// An earlier request to ask for again: same type, same length, same reason.
  final Map<String, dynamic>? copyOf;

  @override
  State<LeaveRequestScreen> createState() => _LeaveRequestScreenState();
}

class _LeaveRequestScreenState extends State<LeaveRequestScreen> {
  final _reason = TextEditingController();
  Map<String, dynamic>? _type;
  late DateTime _from;
  late DateTime _to;
  bool _halfDay = false;
  String _halfPeriod = 'am';
  bool _busy = false;
  List<Map<String, dynamic>> _warnings = [];

  static const _quick = ['Sick', 'Family function', 'Personal work', 'Travel', 'Festival'];

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    final tomorrow = DateTime(now.year, now.month, now.day).add(const Duration(days: 1));
    _from = tomorrow;
    _to = tomorrow;
    _type = widget.initial ?? widget.types.first;
    final copy = widget.copyOf;
    if (copy != null) {
      final id = (copy['type'] as Map)['id'];
      _type = widget.types.where((t) => t['id'] == id).firstOrNull ?? _type;
      final days = ((copy['days'] as num?) ?? 1).ceil();
      _halfDay = copy['half_day'] == true;
      _halfPeriod = '${copy['half_day_period'] ?? 'am'}';
      _to = tomorrow.add(Duration(days: (days - 1).clamp(0, 60)));
      _reason.text = asText(copy['reason']) ?? '';
    }
    _checkBusy();
  }

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  double get _days => _halfDay ? 0.5 : (_to.difference(_from).inDays + 1).toDouble();

  double? get _remaining =>
      _type?['requires_allocation'] == true ? ((_type!['remaining'] as num?) ?? 0).toDouble() : null;

  bool get _overBalance => _remaining != null && _days > _remaining!;

  Future<void> _pickRange() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: now.subtract(const Duration(days: 30)),
      lastDate: now.add(const Duration(days: 365)),
      initialDateRange: DateTimeRange(start: _from, end: _to),
    );
    if (picked == null) return;
    setState(() {
      _from = picked.start;
      _to = picked.end;
    });
    _checkBusy();
  }

  void _preset(int fromOffset, int length) {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day).add(Duration(days: fromOffset));
    setState(() {
      _halfDay = false;
      _from = start;
      _to = start.add(Duration(days: length - 1));
    });
    _checkBusy();
  }

  /// What is already planned on these days, shown beside the dates before the request is sent.
  Future<void> _checkBusy() async {
    try {
      final check = await Services.api.get('/api/v1/leaves/check',
          query: {'start': fmtDate(_from), 'end': fmtDate(_halfDay ? _from : _to)}) as Map<String, dynamic>;
      if (mounted) setState(() => _warnings = ((check['warnings'] as List?) ?? []).cast<Map<String, dynamic>>());
    } catch (_) {
      // Offline or an older server: nothing to show.
    }
  }

  Future<void> _submit() async {
    if (_overBalance) {
      showProblem(context, 'You are asking for ${fmtQty(_days)} days and have ${fmtQty(_remaining!)} left of ${_type!['name']}.');
      return;
    }
    setState(() => _busy = true);
    if (_warnings.isNotEmpty && mounted) {
      final go = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('These days are busy'),
          content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            for (final w in _warnings.take(8))
              Padding(padding: const EdgeInsets.symmetric(vertical: 3), child: Text('• ${w['message']}')),
            const SizedBox(height: 8),
            const Text('Send the request anyway?', style: TextStyle(fontWeight: FontWeight.w700)),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Change dates')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Send anyway')),
          ],
        ),
      );
      if (go != true) {
        if (mounted) setState(() => _busy = false);
        return;
      }
    }
    try {
      await Services.outbox.submit('/api/v1/leaves', {
        'uuid': const Uuid().v4(),
        'type_id': _type!['id'],
        'from': fmtDate(_from),
        'to': fmtDate(_halfDay ? _from : _to),
        'half_day': _halfDay,
        'half_day_period': _halfPeriod,
        'reason': _reason.text.trim(),
      });
      settleAndRefresh();
      if (!mounted) return;
      showSnack(context, 'Request sent for approval');
      Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) showProblem(context, e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _card({required Widget child, EdgeInsets padding = const EdgeInsets.all(14)}) => Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: padding,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(22),
          boxShadow: [BoxShadow(color: const Color(0xFF1B3A7A).withValues(alpha: 0.06), blurRadius: 12, offset: const Offset(0, 4))],
        ),
        child: child,
      );

  @override
  Widget build(BuildContext context) {
    final remaining = _remaining;
    final after = remaining == null ? null : remaining - _days;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Request Time Off')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        children: [
          _card(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Type of leave', style: TextStyle(fontWeight: FontWeight.w900)),
              const SizedBox(height: 10),
              Wrap(spacing: 8, runSpacing: 8, children: [
                for (final type in widget.types)
                  ChoiceChip(
                    label: Text('${type['name']}'),
                    selected: _type?['id'] == type['id'],
                    onSelected: (_) => setState(() => _type = type),
                  ),
              ]),
              if (_type != null) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: AppColors.primary.withValues(alpha: 0.07), borderRadius: BorderRadius.circular(14)),
                  child: Row(children: [
                    const Icon(Icons.account_balance_wallet_rounded, color: AppColors.primary),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        remaining == null
                            ? 'No limit for this type'
                            : '${fmtQty(remaining)} days available · used ${fmtQty((_type!['used'] as num?) ?? 0)} of ${fmtQty((_type!['allocated'] as num?) ?? 0)}'
                                '${((_type!['pending'] as num?) ?? 0) > 0 ? ' · ${fmtQty(_type!['pending'] as num)} waiting' : ''}',
                        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                      ),
                    ),
                  ]),
                ),
                if (asText(_type!['approval']) != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text('Approval: ${_type!['approval']}', style: const TextStyle(color: AppColors.muted, fontSize: 12)),
                  ),
              ],
            ]),
          ),
          _card(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Which days', style: TextStyle(fontWeight: FontWeight.w900)),
              const SizedBox(height: 10),
              Wrap(spacing: 8, runSpacing: 8, children: [
                ActionChip(label: const Text('Tomorrow'), onPressed: () => _preset(1, 1)),
                ActionChip(label: const Text('2 days'), onPressed: () => _preset(1, 2)),
                ActionChip(label: const Text('3 days'), onPressed: () => _preset(1, 3)),
                ActionChip(label: const Text('A week'), onPressed: () => _preset(1, 7)),
              ]),
              const SizedBox(height: 10),
              InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: _halfDay ? null : _pickRange,
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(border: Border.all(color: AppColors.border), borderRadius: BorderRadius.circular(16)),
                  child: Row(children: [
                    const Icon(Icons.date_range_rounded, color: AppColors.primary),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        _halfDay || _from == _to ? _short(_from) : '${_short(_from)}  to  ${_short(_to)}',
                        style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                      decoration: BoxDecoration(
                          color: (_overBalance ? AppColors.danger : AppColors.primary).withValues(alpha: 0.1), borderRadius: BorderRadius.circular(14)),
                      child: Text('${fmtQty(_days)} day${_days == 1 ? '' : 's'}',
                          style: TextStyle(fontWeight: FontWeight.w900, color: _overBalance ? AppColors.danger : AppColors.primary)),
                    ),
                  ]),
                ),
              ),
              SwitchListTile(
                value: _halfDay,
                onChanged: (value) {
                  setState(() {
                    _halfDay = value;
                    if (value) _to = _from;
                  });
                  _checkBusy();
                },
                title: const Text('Half day'),
                contentPadding: EdgeInsets.zero,
              ),
              if (_halfDay)
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'am', label: Text('Morning'), icon: Icon(Icons.wb_sunny_outlined)),
                    ButtonSegment(value: 'pm', label: Text('Afternoon'), icon: Icon(Icons.wb_twilight_rounded)),
                  ],
                  selected: {_halfPeriod},
                  onSelectionChanged: (v) => setState(() => _halfPeriod = v.first),
                ),
              if (after != null)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Text(
                    after < 0 ? 'This is ${fmtQty(-after)} more than you have.' : 'You will have ${fmtQty(after)} days left after this.',
                    style: TextStyle(fontWeight: FontWeight.w700, color: after < 0 ? AppColors.danger : AppColors.success),
                  ),
                ),
            ]),
          ),
          if (_warnings.isNotEmpty)
            _card(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Row(children: [
                  Icon(Icons.warning_amber_rounded, color: AppColors.warning),
                  SizedBox(width: 8),
                  Text('Already planned on these days', style: TextStyle(fontWeight: FontWeight.w900)),
                ]),
                const SizedBox(height: 8),
                for (final w in _warnings.take(5))
                  Padding(padding: const EdgeInsets.symmetric(vertical: 2), child: Text('• ${w['message']}', style: const TextStyle(fontSize: 13))),
              ]),
            ),
          _card(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Reason', style: TextStyle(fontWeight: FontWeight.w900)),
              const SizedBox(height: 10),
              Wrap(spacing: 8, runSpacing: 8, children: [
                for (final q in _quick) ActionChip(label: Text(q), onPressed: () => setState(() => _reason.text = q)),
              ]),
              const SizedBox(height: 10),
              TextField(controller: _reason, maxLines: 3, decoration: const InputDecoration(hintText: 'Tell your manager why')),
            ]),
          ),
          GradientButton(
            label: 'Send for approval',
            icon: Icons.send_rounded,
            busy: _busy,
            onPressed: _busy || _type == null || _type!['can_request'] == false ? null : _submit,
          ),
          if (_type?['can_request'] == false)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text('Nothing left to request for this type.',
                  textAlign: TextAlign.center, style: TextStyle(color: AppColors.danger, fontWeight: FontWeight.w700)),
            ),
        ],
      ),
    );
  }
}
