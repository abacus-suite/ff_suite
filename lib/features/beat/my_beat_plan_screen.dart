import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../../core/format.dart';
import '../../core/services.dart';
import '../../core/theme.dart';
import '../../widgets/common.dart';
import '../../widgets/group_kit.dart';
import 'create_beat_screen.dart';

/// My Beat Plan: the month as a calendar with the beat (or beats) on each day, the day's beats and
/// outlets underneath, and the two ways to add to a day: an existing beat, or a new one.
class MyBeatPlanScreen extends StatefulWidget {
  const MyBeatPlanScreen({super.key});

  @override
  State<MyBeatPlanScreen> createState() => _MyBeatPlanScreenState();
}

class _MyBeatPlanScreenState extends State<MyBeatPlanScreen> {
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);
  DateTime _day = DateUtils.dateOnly(DateTime.now());
  List<Map<String, dynamic>> _plans = [];
  List<Map<String, dynamic>> _routes = [];
  Map<String, dynamic>? _dayData;
  bool _loading = true;
  bool _busy = false;
  String? _error;

  static const _blue = Color(0xFF1A56DB);

  @override
  void initState() {
    super.initState();
    _loadMonth();
    _loadRoutes();
    _loadDay();
  }

  String get _label => Services.auth.profile?.routeLabel ?? 'Beat';

  Future<void> _loadMonth() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final end = DateTime(_month.year, _month.month + 1, 0);
      final list = (await Services.api.get('/api/v1/route-plan/days', query: {
        'member': 'me',
        'start': fmtDate(_month),
        'end': fmtDate(end),
      }) as List)
          .cast<Map<String, dynamic>>();
      if (mounted) setState(() => _plans = list);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadRoutes() async {
    try {
      final list = (await Services.api.get('/api/v1/route-plan/routes', query: {'member': 'me'}) as List)
          .cast<Map<String, dynamic>>();
      if (mounted) setState(() => _routes = list);
    } catch (_) {
      // Without the list "Add an existing beat" simply has nothing to offer.
    }
  }

  Future<void> _loadDay() async {
    try {
      final data = await Services.api.get('/api/v1/beat/today', query: {'date': fmtDate(_day)}) as Map<String, dynamic>;
      if (mounted) setState(() => _dayData = data);
    } catch (_) {
      if (mounted) setState(() => _dayData = null);
    }
  }

  /// The beats planned on a date, in the order they were made.
  List<String> _beatsOn(DateTime day) => [
        for (final p in _plans)
          if ('${p['date']}' == fmtDate(day) && (p['beat'] as Map?)?['name'] != null) '${(p['beat'] as Map)['name']}',
      ];

  /// The beat codes on a date (the name where a beat has no code), for the calendar cells.
  List<String> _codesOn(DateTime day) => [
        for (final p in _plans)
          if ('${p['date']}' == fmtDate(day) && (p['beat'] as Map?)?['name'] != null)
            ('${p['beat_code'] ?? ''}'.isNotEmpty && p['beat_code'] != null)
                ? '${p['beat_code']}'
                : '${(p['beat'] as Map)['name']}',
      ];

  void _shift(int months) {
    setState(() => _month = DateTime(_month.year, _month.month + months));
    _loadMonth();
  }

  void _pick(DateTime day) {
    setState(() {
      _day = day;
      _dayData = null;
    });
    _loadDay();
  }

  /// Add one or more existing beats to the chosen day. A beat still waiting for approval is greyed out.
  Future<void> _addExisting() async {
    final chosen = <int>{};
    final picked = await showModalBottomSheet<List<int>>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheet) => StatefulBuilder(
        builder: (sheet, setSheet) => SafeArea(
          child: SizedBox(
            height: MediaQuery.of(sheet).size.height * 0.7,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                  child: Text('Add an Existing $_label\nFor ${fmtDate(_day)} · select one or more',
                      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16, height: 1.3)),
                ),
                Expanded(
                  child: ListView(
                    children: [
                      for (final r in _routes)
                        Builder(builder: (_) {
                          final pending = '${r['approval_state']}' == 'pending';
                          return CheckboxListTile(
                            value: chosen.contains(r['id']),
                            onChanged: pending
                                ? null
                                : (v) => setSheet(() => v == true ? chosen.add(r['id'] as int) : chosen.remove(r['id'])),
                            title: Text('${r['name']}',
                                style: TextStyle(fontWeight: FontWeight.w700, color: pending ? AppColors.muted : null)),
                            subtitle: Text(
                                pending
                                    ? 'Cannot be selected until approved'
                                    : [
                                        if (r['customer_count'] != null) '${r['customer_count']} outlets',
                                        if (asText(r['city']) != null) '${r['city']}',
                                      ].join(' · '),
                                style: const TextStyle(fontSize: 12.5)),
                            secondary: pending
                                ? const Text('Pending approval',
                                    style: TextStyle(color: AppColors.warning, fontWeight: FontWeight.w700, fontSize: 12))
                                : null,
                          );
                        }),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                  child: SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: chosen.isEmpty ? null : () => Navigator.pop(sheet, chosen.toList()),
                      child: Text('Add selected beats (${chosen.length})'),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (picked == null || picked.isEmpty || !mounted) return;
    setState(() => _busy = true);
    try {
      final routes = <Map<String, dynamic>>[];
      for (final id in picked) {
        final data = await Services.api.get('/api/v1/route-plan/customers',
            query: {'beat_id': id, 'date': fmtDate(_day), 'member': 'me'}) as Map<String, dynamic>;
        final customers = ((data['customers'] as List?) ?? []).cast<Map<String, dynamic>>();
        final ids = [for (final c in customers) c['id'] as int];
        if (ids.isNotEmpty) routes.add({'beat_id': id, 'partner_ids': ids});
      }
      if (routes.isEmpty) {
        if (mounted) showProblem(context, 'The chosen beats have no outlets to plan.');
      } else {
        await Services.outbox.submit('/api/v1/route-plan/days', {
          'uuid': const Uuid().v4(),
          'date': fmtDate(_day),
          'member': 'me',
          'routes': routes,
        });
        settleAndRefresh();
        if (mounted) showSnack(context, 'Added to ${fmtDate(_day)}');
      }
      await _loadMonth();
      await _loadDay();
    } catch (e) {
      if (mounted) showProblem(context, e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _create() async {
    final beat = await Navigator.of(context)
        .push<Map<String, dynamic>>(MaterialPageRoute(builder: (_) => const CreateBeatScreen()));
    if (beat != null && mounted) {
      await _loadRoutes();
      if (!mounted) return;
      showSnack(context, '${beat['name']} sent for approval');
    }
  }

  /// A route comes as {id, name} from the server; show the name, never the map.
  String? _routeName(dynamic route) {
    if (route is Map) return route['name'] == null ? null : '${route['name']}';
    return route == null ? null : '$route';
  }

  @override
  Widget build(BuildContext context) {
    final leading = DateTime(_month.year, _month.month, 1).weekday - 1;
    final days = DateUtils.getDaysInMonth(_month.year, _month.month);
    final beats = _beatsOn(_day);
    final clients = ((_dayData?['clients'] as List?) ?? []).cast<Map<String, dynamic>>();
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: Text('My $_label Plan')),
      body: RefreshIndicator(
        onRefresh: () async {
          await _loadMonth();
          await _loadDay();
        },
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 40),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 8, 8, 12),
                child: Column(children: [
                  Row(children: [
                    IconButton(onPressed: () => _shift(-1), icon: const Icon(Icons.chevron_left_rounded)),
                    Expanded(
                      child: Center(
                        child: Text('${monthNames[_month.month - 1]} ${_month.year}',
                            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                      ),
                    ),
                    IconButton(onPressed: () => _shift(1), icon: const Icon(Icons.chevron_right_rounded)),
                  ]),
                  Row(
                    children: [
                      for (final d in const ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'])
                        Expanded(
                          child: Center(
                            child: Text(d, style: const TextStyle(fontSize: 11.5, color: AppColors.muted, fontWeight: FontWeight.w700)),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  GridView.count(
                    crossAxisCount: 7,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    childAspectRatio: 0.82,
                    children: [
                      for (var i = 0; i < leading; i++) const SizedBox.shrink(),
                      for (var d = 1; d <= days; d++) _cell(DateTime(_month.year, _month.month, d)),
                    ],
                  ),
                ]),
              ),
            ),
            if (_loading) const LinearProgressIndicator(minHeight: 2),
            if (_error != null) ErrorView(message: _error!, onRetry: _loadMonth),
            const SizedBox(height: 10),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(
                    beats.isEmpty
                        ? '${prettyDay(_day)} – no $_label planned. Choose an option below.'
                        : '${prettyDay(_day)} · ${beats.length} ${beats.length == 1 ? _label.toLowerCase() : '${_label.toLowerCase()}s'}',
                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                  ),
                  if (beats.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Wrap(spacing: 8, runSpacing: 6, children: [
                      for (final b in beats)
                        Chip(
                          label: Text(b, style: const TextStyle(fontWeight: FontWeight.w700, color: _blue)),
                          backgroundColor: _blue.withValues(alpha: 0.08),
                          side: BorderSide.none,
                        ),
                    ]),
                  ],
                  const SizedBox(height: 12),
                  Row(children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _busy ? null : _addExisting,
                        icon: const Icon(Icons.add_road_rounded, size: 18),
                        label: Text('Add an Existing $_label'),
                      ),
                    ),
                  ]),
                  const SizedBox(height: 8),
                  Row(children: [
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: _busy ? null : _create,
                        icon: const Icon(Icons.edit_road_rounded, size: 18),
                        label: Text('Create a $_label (Manager Approval)'),
                      ),
                    ),
                  ]),
                ]),
              ),
            ),
            const SizedBox(height: 10),
            if (clients.isNotEmpty)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('${clients.length} outlet${clients.length == 1 ? '' : 's'}',
                        style: const TextStyle(fontWeight: FontWeight.w800)),
                    const SizedBox(height: 6),
                    for (final c in clients)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 5),
                        child: Row(children: [
                          const Icon(Icons.storefront_rounded, size: 18, color: AppColors.primary),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text('${c['name']}${_routeName(c['route']) != null ? '  ·  ${_routeName(c['route'])}' : ''}',
                                maxLines: 1, overflow: TextOverflow.ellipsis),
                          ),
                        ]),
                      ),
                  ]),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _cell(DateTime day) {
    final beats = _codesOn(day);
    final selected = DateUtils.isSameDay(day, _day);
    final today = DateUtils.isSameDay(day, DateTime.now());
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () => _pick(day),
      child: Container(
        margin: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          color: selected ? _blue.withValues(alpha: 0.12) : null,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: selected ? _blue : (today ? AppColors.primary.withValues(alpha: 0.4) : Colors.transparent)),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('${day.day}', style: TextStyle(fontWeight: FontWeight.w800, color: selected ? _blue : AppColors.text)),
            if (beats.isNotEmpty)
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(beats.length > 1 ? '${beats.first} +${beats.length - 1}' : beats.first,
                    maxLines: 1,
                    style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, color: _blue)),
              ),
          ],
        ),
      ),
    );
  }
}
