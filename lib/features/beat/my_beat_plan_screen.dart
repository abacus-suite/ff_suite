import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../../core/format.dart';
import '../../core/services.dart';
import '../../core/theme.dart';
import '../../widgets/common.dart';
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
  bool _loading = true;
  bool _busy = false;
  String? _error;

  static const _blue = Color(0xFF1A56DB);

  @override
  void initState() {
    super.initState();
    _loadMonth();
    _loadRoutes();
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

  /// A tap on a day picks it for the two buttons below, and opens that day's plan if it has any beat.
  void _pick(DateTime day) {
    setState(() => _day = day);
    final planned = [
      for (final p in _plans)
        if ('${p['date']}' == fmtDate(day) && (p['beat'] as Map?)?['id'] != null) (p['beat'] as Map).cast<String, dynamic>(),
    ];
    if (planned.isEmpty) return;
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => BeatDayScreen(day: day, label: _label, planned: planned, routes: _routes),
    ));
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

  @override
  Widget build(BuildContext context) {
    final leading = DateTime(_month.year, _month.month, 1).weekday - 1;
    final days = DateUtils.getDaysInMonth(_month.year, _month.month);
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: Text('My $_label Plan')),
      body: RefreshIndicator(
        onRefresh: _loadMonth,
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
            _actionCard(Icons.flag_rounded, 'Add an Existing $_label', _busy ? null : _addExisting),
            const SizedBox(height: 10),
            _actionCard(Icons.edit_calendar_rounded, 'Create a $_label (Manager Approval)', _busy ? null : _create),
          ],
        ),
      ),
    );
  }

  /// One of the two ways to add to the chosen day.
  Widget _actionCard(IconData icon, String label, VoidCallback? onTap) => InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          decoration: BoxDecoration(
            color: const Color(0xFFFFF7ED),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFFBD5B0)),
          ),
          child: Row(children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(color: _blue.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)),
              child: Icon(icon, size: 19, color: _blue),
            ),
            const SizedBox(width: 12),
            Expanded(child: Text(label, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14.5))),
            const Icon(Icons.chevron_right_rounded, color: AppColors.muted),
          ]),
        ),
      );

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


/// A day's plan, opened by tapping a day: the beat(s) on it, a tick list of the existing beats, and below it
/// the outlets of the ticked beats.
class BeatDayScreen extends StatefulWidget {
  const BeatDayScreen({super.key, required this.day, required this.label, required this.planned, required this.routes});

  final DateTime day;
  final String label;

  /// The beats already planned on this day: `{id, name}`.
  final List<Map<String, dynamic>> planned;

  /// Every existing beat, for the tick list: `{id, name, approval_state, customer_count, ...}`.
  final List<Map<String, dynamic>> routes;

  @override
  State<BeatDayScreen> createState() => _BeatDayScreenState();
}

class _BeatDayScreenState extends State<BeatDayScreen> {
  static const _blue = Color(0xFF1A56DB);

  late final Set<int> _ticked = {for (final b in widget.planned) b['id'] as int};
  final Map<int, List<Map<String, dynamic>>> _outlets = {};
  final Set<int> _loading = {};
  bool _open = false;

  /// Every beat that can be ticked: the existing ones, plus any on this day the list lacks.
  late final List<Map<String, dynamic>> _beats = [
    ...widget.routes,
    for (final b in widget.planned)
      if (!widget.routes.any((r) => r['id'] == b['id'])) b,
  ];

  @override
  void initState() {
    super.initState();
    for (final id in _ticked) {
      _fetch(id);
    }
  }

  String _name(int id) => '${_beats.firstWhere((b) => b['id'] == id, orElse: () => {'name': '#$id'})['name']}';

  Future<void> _fetch(int id) async {
    if (_outlets.containsKey(id) || _loading.contains(id)) return;
    setState(() => _loading.add(id));
    try {
      final data = await Services.api.get('/api/v1/route-plan/customers',
          query: {'beat_id': id, 'date': fmtDate(widget.day), 'member': 'me'}) as Map<String, dynamic>;
      final rows = ((data['customers'] as List?) ?? []).cast<Map<String, dynamic>>();
      if (mounted) setState(() => _outlets[id] = rows);
    } catch (_) {
      if (mounted) setState(() => _outlets[id] = const []);
    } finally {
      if (mounted) setState(() => _loading.remove(id));
    }
  }

  void _toggle(int id, bool on) {
    setState(() => on ? _ticked.add(id) : _ticked.remove(id));
    if (on) _fetch(id);
  }

  int get _outletCount => _ticked.fold(0, (sum, id) => sum + (_outlets[id]?.length ?? 0));

  @override
  Widget build(BuildContext context) {
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    final d = widget.day;
    final title = '${d.day.toString().padLeft(2, '0')} ${months[d.month - 1]} ${d.year}';
    final ids = _ticked.toList();
    final first = ids.isEmpty ? null : _name(ids.first);
    final others = ids.skip(1).map(_name).toList();
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
          const Text('Opened by tapping a day', style: TextStyle(fontSize: 11.5, color: AppColors.muted, fontWeight: FontWeight.w500)),
        ]),
      ),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 32), children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(children: [
              Row(children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(first ?? 'No ${widget.label.toLowerCase()} ticked',
                        style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: _blue)),
                    if (first != null)
                      Text(
                        '${others.isEmpty ? '' : '+ ${others.join(', ')} · '}$_outletCount outlet${_outletCount == 1 ? '' : 's'}',
                        style: const TextStyle(fontSize: 11.5, color: AppColors.muted),
                      ),
                  ]),
                ),
                InkWell(
                  borderRadius: BorderRadius.circular(18),
                  onTap: () => setState(() => _open = !_open),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                    decoration: BoxDecoration(color: _blue.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(18)),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Text('${ids.length} ${ids.length == 1 ? widget.label.toLowerCase() : '${widget.label.toLowerCase()}s'}',
                          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5, color: _blue)),
                      Icon(_open ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded, size: 18, color: _blue),
                    ]),
                  ),
                ),
              ]),
              if (_open) ...[
                const SizedBox(height: 8),
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Column(children: [
                    for (final b in _beats)
                      Builder(builder: (_) {
                        final id = b['id'] as int;
                        final pending = '${b['approval_state']}' == 'pending';
                        return CheckboxListTile(
                          dense: true,
                          value: _ticked.contains(id),
                          onChanged: pending ? null : (v) => _toggle(id, v == true),
                          controlAffinity: ListTileControlAffinity.leading,
                          title: Text('${b['name']}',
                              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: pending ? AppColors.muted : null)),
                          secondary: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: (pending ? AppColors.warning : AppColors.success).withValues(alpha: 0.14),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(pending ? 'Pending' : 'Approved',
                                style: TextStyle(
                                    fontSize: 10.5, fontWeight: FontWeight.w800, color: pending ? AppColors.warning : AppColors.success)),
                          ),
                        );
                      }),
                  ]),
                ),
              ],
            ]),
          ),
        ),
        const SizedBox(height: 4),
        if (_loading.isNotEmpty) const LinearProgressIndicator(minHeight: 2),
        for (final id in ids)
          for (final c in _outlets[id] ?? const <Map<String, dynamic>>[])
            Card(
              margin: const EdgeInsets.only(top: 8),
              child: ListTile(
                dense: true,
                title: Text('${c['name']}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5)),
                subtitle: Text(_name(id), style: const TextStyle(fontSize: 11.5)),
              ),
            ),
        if (ids.isNotEmpty)
          const Padding(
            padding: EdgeInsets.fromLTRB(4, 12, 4, 0),
            child: Text('… all outlets of the selected beats',
                style: TextStyle(fontSize: 11.5, fontStyle: FontStyle.italic, color: AppColors.muted)),
          ),
      ]),
    );
  }
}
