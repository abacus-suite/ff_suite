import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/format.dart';
import '../../core/services.dart';
import '../../core/theme.dart';
import '../../widgets/common.dart';
import '../../widgets/skeleton.dart';
import '../approvals/approvals_screen.dart';
import '../tasks/tasks_screen.dart';
import '../team/team_beat_plan_screen.dart';
import '../team/team_live_screen.dart';
import '../team/team_target_screen.dart';

const _blue = Color(0xFF1D4ED8);
const _green = Color(0xFF16A34A);
const _orange = Color(0xFFEA580C);
const _red = Color(0xFFDC2626);
const _sky = Color(0xFF2563EB);

String initials(String name) {
  final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
  if (parts.isEmpty) return '?';
  if (parts.length == 1) return parts.first[0].toUpperCase();
  return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
}

List<Map<String, dynamic>> _rows(dynamic v) => ((v as List?) ?? []).cast<Map<String, dynamic>>();

/// Manager Mode Home: the team today, approvals, beat plan summary, target, overdue, the tasks I gave,
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
  String? _date;
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
      final home = await Services.api.get('/api/v1/team/home',
          query: {if (_date != null) 'date': _date! else 'period': _period}) as Map<String, dynamic>;
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

  Widget _card({required Widget child, EdgeInsets padding = const EdgeInsets.all(14), VoidCallback? onTap}) =>
      Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppColors.border.withValues(alpha: 0.7)),
        ),
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(18),
          child: InkWell(borderRadius: BorderRadius.circular(18), onTap: onTap, child: Padding(padding: padding, child: child)),
        ),
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
  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date == null ? DateTime.now() : DateTime.parse(_date!),
      firstDate: DateTime(2024),
      lastDate: DateTime.now(),
    );
    if (picked != null) {
      setState(() {
        _date = fmtDate(picked);
        _period = 'date';
      });
      _load();
    }
  }

  void _openPeople(String key) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => PeopleScreen(initial: key, period: _period, date: _date),
    ));
  }

  Widget _attendance() {
    final team = ((_home?['team_size'] as num?) ?? 0).toInt();
    final present = _count('present');
    final away = _count('absent');
    final leave = _count('leave');
    Widget chip(String key, String label) {
      final selected = _date == null && _period == key;
      return Padding(
        padding: const EdgeInsets.only(right: 6),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: () {
            setState(() {
              _period = key;
              _date = null;
            });
            _load();
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: BoxDecoration(
              color: selected ? Colors.white : Colors.white.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: Colors.white.withValues(alpha: 0.5)),
            ),
            child: Text(selected ? '✓ $label' : label,
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: selected ? _blue : Colors.white)),
          ),
        ),
      );
    }

    Widget box(String key, String label, Color tint, Color bg) => Expanded(
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: () => _openPeople(key),
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 3),
              padding: const EdgeInsets.symmetric(vertical: 11),
              decoration: BoxDecoration(
                color: bg,
                borderRadius: BorderRadius.circular(14),
                border: Border(bottom: BorderSide(color: tint, width: 3)),
              ),
              child: Column(children: [
                Text('${_count(key)}', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 21, color: tint)),
                Text(label, style: TextStyle(fontSize: 11.5, color: tint, fontWeight: FontWeight.w800)),
              ]),
            ),
          ),
        );

    final ratio = team == 0 ? 0.0 : (present / team).clamp(0.0, 1.0);
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
            colors: [Color(0xFF1E40AF), Color(0xFF2563EB), Color(0xFF3B82F6)],
            begin: Alignment.topLeft, end: Alignment.bottomRight),
        borderRadius: BorderRadius.circular(22),
        boxShadow: [BoxShadow(color: _blue.withValues(alpha: 0.28), blurRadius: 16, offset: const Offset(0, 8))],
      ),
      child: Column(children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(children: [
            InkWell(
              onTap: _pickDate,
              borderRadius: BorderRadius.circular(18),
              child: Container(
                width: 34,
                height: 34,
                margin: const EdgeInsets.only(right: 6),
                decoration: BoxDecoration(
                  color: _date != null ? Colors.white : Colors.white.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.5)),
                ),
                child: Icon(Icons.calendar_month_rounded, size: 18, color: _date != null ? _blue : Colors.white),
              ),
            ),
            chip('today', 'Today'),
            chip('yesterday', 'Yesterday'),
            chip('week', 'This week'),
            chip('month', 'This month'),
          ]),
        ),
        const SizedBox(height: 12),
        InkWell(
          onTap: () => _openPeople('present'),
          child: Row(children: [
            SizedBox(
              width: 74,
              height: 74,
              child: Stack(alignment: Alignment.center, children: [
                SizedBox(
                  width: 74,
                  height: 74,
                  child: CircularProgressIndicator(
                      value: ratio, strokeWidth: 6, color: Colors.white, backgroundColor: Colors.white.withValues(alpha: 0.25)),
                ),
                Column(mainAxisSize: MainAxisSize.min, children: [
                  Text('$present', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 22, height: 1)),
                  Text('of $team', style: const TextStyle(color: Colors.white70, fontSize: 11)),
                ]),
              ]),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Your team today', style: TextStyle(color: Colors.white70, fontSize: 12)),
                Text('$present present now',
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 19)),
                Text('$away absent · $leave on leave', style: const TextStyle(color: Colors.white70, fontSize: 12.5)),
              ]),
            ),
            const Icon(Icons.chevron_right_rounded, color: Colors.white),
          ]),
        ),
        const SizedBox(height: 12),
        Row(children: [
          box('present', 'Present', _green, const Color(0xFFDCFCE7)),
          box('late', 'Late', _orange, const Color(0xFFFFEDD5)),
          box('absent', 'Absent', _red, const Color(0xFFFEE2E2)),
          box('leave', 'On Leave', _sky, const Color(0xFFDBEAFE)),
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
                  ? const [Color(0xFF059669), Color(0xFF10B981)]
                  : const [Color(0xFF059669), Color(0xFF10B981)],
            ),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(children: [
            const Icon(Icons.fact_check_rounded, color: Colors.white, size: 28),
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
              width: 40,
              height: 40,
              alignment: Alignment.center,
              decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
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
    Widget tile(String label, int value, Color tint, Color bg, {bool first = false}) {
      final share = first ? 100 : (planned == 0 ? 0 : (value * 100 / planned).round());
      return Expanded(
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 3),
          padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
          decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(12)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Align(
                alignment: Alignment.centerRight,
                child: Text('$share%', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, color: tint))),
            Text('$value', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 20)),
            Text(label, style: const TextStyle(fontSize: 11, color: AppColors.muted)),
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                  value: first ? 1 : (planned == 0 ? 0 : value / planned),
                  minHeight: 4,
                  color: tint,
                  backgroundColor: tint.withValues(alpha: 0.18)),
            ),
          ]),
        ),
      );
    }

    return _card(
      onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const TeamBeatPlanScreen())),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.event_note_rounded, color: _blue, size: 20),
          const SizedBox(width: 8),
          const Expanded(child: Text('Team Beat Plan Summary', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15))),
          const Text('View All', style: TextStyle(color: _blue, fontWeight: FontWeight.w800, fontSize: 12.5)),
        ]),
        const SizedBox(height: 10),
        Row(children: [
          tile('Planned', planned, _sky, const Color(0xFFDBEAFE), first: true),
          tile('Visited', n('visited'), _green, const Color(0xFFDCFCE7)),
          tile('Pending', n('pending'), _orange, const Color(0xFFFFEDD5)),
          tile('Cancelled', n('cancelled'), _red, const Color(0xFFFEE2E2)),
        ]),
      ]),
    );
  }

  // ------------------------------------------------------------------ team target
  Widget _teamTarget() {
    final t = _target!;
    final bottles = ((t['bottles'] as num?) ?? 0).toInt();
    final bottleTarget = ((t['bottle_target'] as num?) ?? 0).toInt();
    final outlets = ((t['outlets'] as num?) ?? 0).toInt();
    final outletTarget = ((t['outlet_target'] as num?) ?? 0).toInt();
    Widget bar(String label, int actual, int target, String unit) {
      final ratio = target == 0 ? 0.0 : (actual / target).clamp(0.0, 1.0);
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text(label, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13))),
            Text(target == 0 ? 'No target' : '${(ratio * 100).round()}%',
                style: const TextStyle(fontWeight: FontWeight.w900, color: _orange)),
          ]),
          const SizedBox(height: 5),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
                value: ratio, minHeight: 9, color: _orange, backgroundColor: AppColors.border.withValues(alpha: 0.5)),
          ),
          const SizedBox(height: 3),
          Text('${_money(actual)} of ${_money(target)} $unit', style: const TextStyle(fontSize: 11.5, color: AppColors.muted)),
        ]),
      );
    }

    final month = monthNames[DateTime.now().month - 1];
    return _card(
      onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const TeamTargetScreen())),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.track_changes_rounded, color: _red, size: 20),
          const SizedBox(width: 8),
          Expanded(
              child: Text('Team Target – $month\n(month to date)',
                  style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14.5, height: 1.25))),
          const Icon(Icons.chevron_right_rounded, color: AppColors.muted),
        ]),
        const SizedBox(height: 10),
        bar('No. of bottles', bottles, bottleTarget, 'bottles'),
        bar('No. of outlets onboarded', outlets, outletTarget, 'outlets'),
      ]),
    );
  }

  String _money(int v) {
    final s = v.toString();
    final buf = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write(',');
      buf.write(s[i]);
    }
    return buf.toString();
  }

  // ------------------------------------------------------------------ overdue
  Widget _overdue() {
    final o = _block('overdue');
    final currency = _home?['currency'] as String?;
    final items = _rows(o['items']);
    Widget part(IconData icon, Color tint, Color bg, String value, String label) => Expanded(
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 3),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(12)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(icon, size: 18, color: tint),
              const SizedBox(height: 4),
              Text(value, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15)),
              Text(label, style: const TextStyle(fontSize: 11.5, color: AppColors.muted)),
            ]),
          ),
        );
    return _card(
      onTap: () => Navigator.of(context)
          .push(MaterialPageRoute(builder: (_) => OverdueScreen(items: items, currency: currency))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.account_balance_wallet_rounded, color: _red, size: 20),
          const SizedBox(width: 8),
          const Expanded(child: Text('Overdue', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15))),
        ]),
        const SizedBox(height: 4),
        Row(children: [
          Text(fmtMoney(o['total'] as num?, currency),
              style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 24, color: _red)),
          const Spacer(),
          const Text('By outlet, distributor', style: TextStyle(fontSize: 12, color: AppColors.muted)),
          const Icon(Icons.chevron_right_rounded, size: 18, color: AppColors.muted),
        ]),
        const SizedBox(height: 10),
        Row(children: [
          part(Icons.storefront_rounded, _sky, const Color(0xFFDBEAFE), fmtMoney(o['outlet'] as num?, currency), 'Outlet overdue'),
          part(Icons.local_shipping_rounded, _orange, const Color(0xFFFFF4D6),
              fmtMoney(o['distributor'] as num?, currency), 'Distributor overdue'),
        ]),
      ]),
    );
  }

  // ------------------------------------------------------------------ tasks I gave
  String _taskTab = 'pending';

  /// One look for every section on Home: a tinted icon tile, the title, and an optional action.
  Widget _head(IconData icon, Color tint, String title, {String? action, VoidCallback? onAction}) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Row(children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(color: tint.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(11)),
            child: Icon(icon, color: tint, size: 19),
          ),
          const SizedBox(width: 10),
          Expanded(child: Text(title, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15.5))),
          if (action != null)
            InkWell(
              onTap: onAction,
              child: Text(action, style: TextStyle(color: tint, fontWeight: FontWeight.w800, fontSize: 12.5)),
            ),
        ]),
      );

  Widget _tasks() {
    final t = _block('tasks');
    final latest = _rows(t['latest']);
    Widget stat(String key, String label, num? v, Color tint) {
      final selected = _taskTab == key;
      return Expanded(
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => setState(() => _taskTab = key),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            margin: const EdgeInsets.symmetric(horizontal: 3),
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              color: selected ? tint.withValues(alpha: 0.14) : const Color(0xFFF6F8FC),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: selected ? tint : Colors.transparent, width: 1.4),
            ),
            child: Column(children: [
              Text('${v ?? 0}', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 20, color: tint)),
              Text(label, style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: AppColors.muted)),
            ]),
          ),
        ),
      );
    }

    final shown = latest.where((x) => _taskTab == 'overdue' ? x['status'] == 'overdue' : _taskTab == 'done' ? false : true).toList();
    return _card(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _head(Icons.assignment_turned_in_rounded, _blue, 'Tasks assigned by me',
            action: 'View all',
            onAction: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const TasksScreen()))),
        Row(children: [
          stat('pending', 'Pending', t['pending'] as num?, _orange),
          stat('done', 'Done', t['done'] as num?, _green),
          stat('overdue', 'Overdue', t['overdue'] as num?, _red),
        ]),
        const SizedBox(height: 12),
        if (shown.isEmpty)
          Container(
            padding: const EdgeInsets.symmetric(vertical: 18),
            alignment: Alignment.center,
            child: const Text('Nothing here.', style: TextStyle(color: AppColors.muted)),
          ),
        for (final task in shown)
          Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.fromLTRB(0, 0, 10, 0),
            decoration: BoxDecoration(color: const Color(0xFFF6F8FC), borderRadius: BorderRadius.circular(14)),
            child: IntrinsicHeight(
              child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Container(
                  width: 4,
                  decoration: BoxDecoration(
                    color: task['status'] == 'overdue' ? _red : _orange,
                    borderRadius: const BorderRadius.horizontal(left: Radius.circular(14)),
                  ),
                ),
                const SizedBox(width: 10),
                Center(
                  child: CircleAvatar(
                    radius: 16,
                    backgroundColor: Colors.white,
                    child: Text(initials('${task['to']}'),
                        style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 11, color: _blue)),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('${task['name']}',
                          maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800)),
                      const SizedBox(height: 2),
                      Text('To: ${task['to']}${task['due'] != null ? ' \u00B7 due ${_short('${task['due']}')}' : ''}',
                          style: const TextStyle(fontSize: 11.5, color: AppColors.muted)),
                    ]),
                  ),
                ),
                Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: (task['status'] == 'overdue' ? _red : _orange).withValues(alpha: 0.13),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(task['status'] == 'overdue' ? 'Overdue' : 'Pending',
                        style: TextStyle(
                            color: task['status'] == 'overdue' ? _red : _orange,
                            fontWeight: FontWeight.w900,
                            fontSize: 11)),
                  ),
                ),
              ]),
            ),
          ),
      ]),
    );
  }

  String _short(String iso) {
    final d = DateTime.tryParse(iso);
    return d == null ? iso : '${d.day.toString().padLeft(2, '0')} ${monthNames[d.month - 1].substring(0, 3)}';
  }

  // ------------------------------------------------------------------ alerts
  Widget _alerts() {
    final alerts = _rows(_home?['alerts']);
    if (alerts.isEmpty) return const SizedBox.shrink();
    const icons = {
      'beat_not_planned': (Icons.edit_calendar_rounded, _sky),
      'missed_checkout': (Icons.logout_rounded, _orange),
      'expenses_not_sent': (Icons.receipt_long_rounded, _red),
    };
    return _card(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _head(Icons.notifications_active_rounded, _orange, 'Alerts'),
        for (final (i, a) in alerts.indexed) ...[
          if (i > 0) const Divider(height: 18),
          Row(children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: (icons['${a['key']}']?.$2 ?? _orange).withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(13),
              ),
              child: Icon(icons['${a['key']}']?.$1 ?? Icons.warning_amber_rounded,
                  color: icons['${a['key']}']?.$2 ?? _orange, size: 21),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${a['title']}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5)),
                const SizedBox(height: 2),
                Text(((a['names'] as List?) ?? []).join(', '),
                    maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12, color: AppColors.muted)),
              ]),
            ),
            Container(
              constraints: const BoxConstraints(minWidth: 28),
              height: 28,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: icons['${a['key']}']?.$2 ?? _orange,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Text('${a['count']}',
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 12.5)),
            ),
          ]),
        ],
      ]),
    );
  }

  // ------------------------------------------------------------------ live map
  Widget _liveMap() {
    final working = _count('present');
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
            colors: [Color(0xFF0F172A), Color(0xFF1E293B)], begin: Alignment.topLeft, end: Alignment.bottomRight),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.18), blurRadius: 14, offset: const Offset(0, 6))],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const TeamLiveScreen())),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(children: [
              Stack(alignment: Alignment.center, children: [
                Container(
                  width: 54,
                  height: 54,
                  decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(18)),
                ),
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                      gradient: const LinearGradient(colors: [Color(0xFF34D399), Color(0xFF10B981)]),
                      borderRadius: BorderRadius.circular(13)),
                  child: const Icon(Icons.my_location_rounded, color: Colors.white, size: 21),
                ),
              ]),
              const SizedBox(width: 14),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('Live map',
                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 16.5)),
                  const SizedBox(height: 2),
                  Text('$working on duty \u00B7 see where your team is right now',
                      style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 12)),
                ]),
              ),
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.12), shape: BoxShape.circle),
                child: const Icon(Icons.arrow_forward_rounded, color: Colors.white, size: 19),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

/// The people behind one attendance box: tabs Present / Late / Absent / On Leave, a calendar for the date,
/// and for each person the check-in time and place with a call button.
class PeopleScreen extends StatefulWidget {
  const PeopleScreen({super.key, required this.initial, required this.period, this.date});

  final String initial;
  final String period;
  final String? date;

  @override
  State<PeopleScreen> createState() => _PeopleScreenState();
}

class _PeopleScreenState extends State<PeopleScreen> {
  late String _tab = widget.initial;
  late String? _date = widget.date;
  late String _period = widget.period;
  Map<String, dynamic>? _data;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final d = await Services.api.get('/api/v1/team/home',
          query: {if (_date != null) 'date': _date! else 'period': _period == 'date' ? 'today' : _period}) as Map<String, dynamic>;
      if (mounted) setState(() => _data = d);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date == null ? DateTime.now() : DateTime.parse(_date!),
      firstDate: DateTime(2024),
      lastDate: DateTime.now(),
    );
    if (picked != null) {
      setState(() {
        _date = fmtDate(picked);
        _data = null;
      });
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final att = (_data?['attendance'] as Map?)?.cast<String, dynamic>() ?? const {};
    int count(String k) => (((att[k] as Map?)?['count']) as num? ?? 0).toInt();
    final people = _rows((att[_tab] as Map?)?['people']);
    const names = {'present': 'Present', 'late': 'Late', 'absent': 'Absent', 'leave': 'On Leave'};
    const tints = {'present': _green, 'late': _orange, 'absent': _red, 'leave': _sky};
    final subtitle = _date != null ? _date! : (_period == 'today' ? 'Today' : _period);
    return Scaffold(
      backgroundColor: const Color(0xFFEEF3FB),
      appBar: AppBar(
        backgroundColor: const Color(0xFFEEF3FB),
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('${names[_tab]} (${count(_tab)})', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
          Text('$subtitle · tap a name for his day',
              style: const TextStyle(fontSize: 11.5, color: AppColors.muted, fontWeight: FontWeight.w500)),
        ]),
        actions: [IconButton(onPressed: _pickDate, icon: const Icon(Icons.calendar_month_rounded))],
      ),
      body: _error != null
          ? ErrorView(message: _error!, onRetry: _load)
          : _data == null
              ? const LoadingView()
              : Column(children: [
                  SizedBox(
                    height: 52,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      children: [
                        for (final k in ['present', 'late', 'absent', 'leave'])
                          Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: ChoiceChip(
                              label: Text('${names[k]} ${count(k)}',
                                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5)),
                              selected: _tab == k,
                              showCheckmark: false,
                              selectedColor: (tints[k] ?? _blue).withValues(alpha: 0.18),
                              onSelected: (_) => setState(() => _tab = k),
                            ),
                          ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: people.isEmpty
                        ? const Center(child: Text('Nobody here.', style: TextStyle(color: AppColors.muted)))
                        : ListView(padding: const EdgeInsets.fromLTRB(16, 0, 16, 24), children: [
                            for (final p in people)
                              Container(
                                margin: const EdgeInsets.only(bottom: 8),
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
                                child: Row(children: [
                                  CircleAvatar(
                                    backgroundColor: const Color(0xFFDBEAFE),
                                    child: Text(initials('${p['name']}'),
                                        style: const TextStyle(fontWeight: FontWeight.w900, color: _blue, fontSize: 13)),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                      Text('${p['name']}', style: const TextStyle(fontWeight: FontWeight.w800)),
                                      Text([
                                        if (p['in_at'] != null) 'In ${fmtTime(p['in_at'])}',
                                        if (p['out_at'] != null) 'Out ${fmtTime(p['out_at'])}',
                                        if (p['place'] != null) '${p['place']}' else if (p['job'] != null) '${p['job']}',
                                      ].join(' · '),
                                          maxLines: 1, overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(fontSize: 11.5, color: AppColors.muted)),
                                    ]),
                                  ),
                                  if (p['late'] == true || _tab == 'late')
                                    Container(
                                      margin: const EdgeInsets.only(right: 8),
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                      decoration: BoxDecoration(
                                          color: const Color(0xFFFFEDD5), borderRadius: BorderRadius.circular(10)),
                                      child: const Text('Late',
                                          style: TextStyle(color: _orange, fontWeight: FontWeight.w800, fontSize: 11)),
                                    ),
                                  if (p['phone'] != null)
                                    InkWell(
                                      onTap: () => launchUrl(Uri(scheme: 'tel', path: '${p['phone']}')),
                                      child: Container(
                                        width: 38,
                                        height: 38,
                                        decoration: const BoxDecoration(color: Color(0xFFDBEAFE), shape: BoxShape.circle),
                                        child: const Icon(Icons.call_rounded, color: _blue, size: 19),
                                      ),
                                    ),
                                ]),
                              ),
                          ]),
                  ),
                ]),
    );
  }
}

/// Overdue by outlet or by distributor, with the employee, the days and the invoices.
class OverdueScreen extends StatefulWidget {
  const OverdueScreen({super.key, required this.items, required this.currency});

  final List<Map<String, dynamic>> items;
  final String? currency;

  @override
  State<OverdueScreen> createState() => _OverdueScreenState();
}

class _OverdueScreenState extends State<OverdueScreen> {
  String _kind = 'outlet';

  @override
  Widget build(BuildContext context) {
    final rows = widget.items.where((i) => i['kind'] == _kind).toList();
    final today = DateTime.now();
    return Scaffold(
      backgroundColor: const Color(0xFFEEF3FB),
      appBar: AppBar(
        backgroundColor: const Color(0xFFEEF3FB),
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Overdue', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
          Text('Team · as on ${today.day.toString().padLeft(2, '0')} ${monthNames[today.month - 1].substring(0, 3)}',
              style: const TextStyle(fontSize: 11.5, color: AppColors.muted, fontWeight: FontWeight.w500)),
        ]),
      ),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: Row(children: [
            for (final (key, label) in [('outlet', 'Outlets'), ('distributor', 'Distributors')])
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  label: Text(_kind == key ? '✓ $label' : label,
                      style: const TextStyle(fontWeight: FontWeight.w800)),
                  selected: _kind == key,
                  showCheckmark: false,
                  selectedColor: const Color(0xFFDBEAFE),
                  onSelected: (_) => setState(() => _kind = key),
                ),
              ),
          ]),
        ),
        Expanded(
          child: rows.isEmpty
              ? const Center(child: Text('Nothing overdue.', style: TextStyle(color: AppColors.muted)))
              : ListView(padding: const EdgeInsets.fromLTRB(16, 0, 16, 24), children: [
                  for (final r in rows)
                    Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
                      child: Row(children: [
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text('${(r['customer'] as Map)['name']}', style: const TextStyle(fontWeight: FontWeight.w800)),
                            Text('${r['employee'] ?? ''} · ${r['days']} days',
                                style: const TextStyle(fontSize: 12, color: AppColors.muted)),
                          ]),
                        ),
                        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                          Text(fmtMoney(r['amount'] as num?, widget.currency),
                              style: const TextStyle(fontWeight: FontWeight.w900, color: _red)),
                          Text('${r['invoices']} invoice${r['invoices'] == 1 ? '' : 's'}',
                              style: const TextStyle(fontSize: 11.5, color: AppColors.muted)),
                        ]),
                      ]),
                    ),
                ]),
        ),
      ]),
    );
  }
}
