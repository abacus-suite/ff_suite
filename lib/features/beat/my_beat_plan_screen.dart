import 'package:flutter/foundation.dart' show setEquals;
import '../../widgets/report_download.dart';
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../../core/api_client.dart';
import '../../core/format.dart';
import '../../core/services.dart';
import '../../core/theme.dart';
import '../../widgets/common.dart';
import 'create_beat_screen.dart';
import 'my_beats.dart';

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

  /// Calendar (the month with the day's beats) or My Beats (the beat list).
  bool _myBeats = false;

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
  Future<void> _pick(DateTime day) async {
    setState(() => _day = day);
    final entries = [
      for (final p in _plans)
        if ('${p['date']}' == fmtDate(day) && (p['beat'] as Map?)?['id'] != null) p,
    ];
    if (entries.isEmpty) return;
    final changed = await Navigator.of(context).push<bool>(MaterialPageRoute(
      builder: (_) => BeatDayScreen(
        day: day,
        label: _label,
        planned: [for (final p in entries) (p['beat'] as Map).cast<String, dynamic>()],
        routes: _routes,
        entries: entries,
      ),
    ));
    // A beat removed from the day: the calendar cell changes with it.
    if (changed == true) await _loadMonth();
  }

  /// Add one or more existing beats to the chosen day. A beat still waiting for approval is greyed out.
  Future<void> _addExisting() async {
    final picked = await Navigator.of(context).push<Map<int, List<int>>>(
      MaterialPageRoute(builder: (_) => AddExistingBeatScreen(day: _day, label: _label, routes: _routes)),
    );
    if (picked == null || picked.isEmpty || !mounted) return;
    setState(() => _busy = true);
    try {
      await Services.outbox.submit('/api/v1/route-plan/days', {
        'uuid': const Uuid().v4(),
        'date': fmtDate(_day),
        'member': 'me',
        'routes': [for (final e in picked.entries) {'beat_id': e.key, 'partner_ids': e.value}],
      });
      settleAndRefresh();
      if (mounted) showSnack(context, 'Added to ${fmtDate(_day)}');
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
      appBar: AppBar(title: Text('My $_label Plan'), actions: [const ReportDownloadButton(reportKey: 'route_plans', title: 'Beat plan')]),
      body: RefreshIndicator(
        onRefresh: () => _myBeats ? _loadRoutes() : _loadMonth(),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 40),
          children: [
            _viewSwitch(),
            const SizedBox(height: 10),
            if (_myBeats)
              MyBeatsList(routes: _routes, label: _label, onChanged: _loadRoutes)
            else ...[
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
            if (_day.isBefore(DateUtils.dateOnly(DateTime.now())))
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
                decoration: BoxDecoration(
                  color: AppColors.muted.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Text('A day gone by can be viewed but not changed. Pick today or an upcoming day to plan.',
                    style: TextStyle(fontSize: 12.5, color: AppColors.muted, fontWeight: FontWeight.w600)),
              )
            else ...[
              // An empty day picked: say so, right above the two ways to fill it.
              if (!_loading && _error == null && _codesOn(_day).isEmpty) ...[
                _emptyDayNote(),
                const SizedBox(height: 10),
              ],
              _actionCard(Icons.flag_rounded, 'Add an Existing $_label', _busy ? null : _addExisting),
              const SizedBox(height: 10),
              _actionCard(Icons.edit_calendar_rounded, 'Create a $_label (Manager Approval)', _busy ? null : _create),
            ],
            ],
          ],
        ),
      ),
    );
  }

  /// Calendar | My Beats, as two halves of one pill.
  Widget _viewSwitch() {
    Widget half(String text, bool on, VoidCallback onTap) => Expanded(
          child: InkWell(
            borderRadius: BorderRadius.circular(22),
            onTap: onTap,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(
                color: on ? _blue.withValues(alpha: 0.12) : Colors.transparent,
                borderRadius: BorderRadius.circular(22),
              ),
              child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                if (on) const Icon(Icons.check_rounded, size: 16, color: _blue),
                if (on) const SizedBox(width: 4),
                Text(text, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5, color: on ? _blue : AppColors.text)),
              ]),
            ),
          ),
        );
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(25),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(children: [
        half('Calendar', !_myBeats, () => setState(() => _myBeats = false)),
        half('My ${_label}s', _myBeats, () {
          setState(() => _myBeats = true);
          _loadRoutes();
        }),
      ]),
    );
  }

  /// "20 Oct – no beat planned. Choose an option below."
  Widget _emptyDayNote() => Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
        decoration: BoxDecoration(
          color: AppColors.warning.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.warning.withValues(alpha: 0.35)),
        ),
        child: Text(
            '${_day.day} ${monthNames[_day.month - 1].substring(0, 3)} – no ${_label.toLowerCase()} planned. '
            'Choose an option below.',
            style: const TextStyle(fontSize: 12.5, color: Color(0xFF9A3412), fontWeight: FontWeight.w600)),
      );

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


/// One beat on a day, with its outlets and what is ticked.
class _DayBeat {
  _DayBeat({required this.id, required this.name, required this.code, required this.canEdit});

  final int id;
  final String name;
  final String code;

  /// A beat I drew myself can be unplanned, one my manager assigned cannot.
  final bool canEdit;

  /// The beat's outlets (null until they have been fetched) and the ones ticked as planned.
  List<Map<String, dynamic>>? outlets;
  Set<int> sel = {};
  Set<int> initial = {};
  bool open = false;
  bool loading = false;

  /// Unticked before its outlets were known: the whole beat comes off the day.
  bool removed = false;

  Set<int> get visited => {
        for (final o in outlets ?? const <Map<String, dynamic>>[])
          if (o['visited'] == true) o['id'] as int,
      };

  /// Work has started on this beat today (an outlet was visited): nothing on it can be unplanned any more.
  bool get started => visited.isNotEmpty;

  /// What the beat's own tick shows: all planned, some, or none.
  bool? get value {
    if (removed) return false;
    final all = outlets;
    if (all == null) return true;
    if (sel.isEmpty) return false;
    return sel.length == all.length ? true : null;
  }

  bool get changed => outlets == null ? removed : !setEquals(sel, initial);
}


/// A day's plan, opened by tapping a day: the beats on it, each one a tick (the whole beat) that opens to its
/// outlets (each a tick). Everything starts ticked because it is planned; unticking unplans it. The + adds an
/// existing beat, whole or with only the outlets picked.
class BeatDayScreen extends StatefulWidget {
  const BeatDayScreen(
      {super.key, required this.day, required this.label, required this.planned, required this.routes, this.entries = const []});

  final DateTime day;
  final String label;

  /// The day's plan lines from `/api/v1/route-plan/days`: `{date, beat, beat_code, added_by, ...}`. They say
  /// who put each beat on the day: a beat I added myself can be unplanned, my manager's cannot.
  final List<Map<String, dynamic>> entries;

  /// The beats already planned on this day: `{id, name}`.
  final List<Map<String, dynamic>> planned;

  /// Every existing beat, for the + : `{id, name, approval_state, customer_count, ...}`.
  final List<Map<String, dynamic>> routes;

  @override
  State<BeatDayScreen> createState() => _BeatDayScreenState();
}

class _BeatDayScreenState extends State<BeatDayScreen> {
  static const _blue = Color(0xFF1A56DB);

  late final List<_DayBeat> _beats = [for (final b in widget.planned) _beatOf(b)]
    ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  bool _saving = false;

  /// Anything saved or added here: the calendar reloads when the screen closes.
  bool _saved = false;

  bool get _past => widget.day.isBefore(DateUtils.dateOnly(DateTime.now()));
  bool get _dirty => _beats.any((b) => b.changed);

  Map<String, dynamic> _entry(int id) =>
      widget.entries.firstWhere((e) => (e['beat'] as Map?)?['id'] == id, orElse: () => <String, dynamic>{});

  Map<String, dynamic> _route(int id) => widget.routes.firstWhere((b) => b['id'] == id, orElse: () => {'id': id});

  _DayBeat _beatOf(Map<String, dynamic> b) {
    final id = b['id'] as int;
    final entry = _entry(id);
    final route = _route(id);
    final byManager = entry['assigned_by_manager'] == true;
    final mine = byManager
        ? false
        : (entry['added_by'] is Map ? beatIsMine({'added_by': entry['added_by']}) : beatIsMine(route));
    final name = '${b['name'] ?? route['name'] ?? '#$id'}';
    return _DayBeat(id: id, name: name, code: asText(entry['beat_code']) ?? asText(route['code']) ?? name, canEdit: mine && !_past);
  }

  @override
  void initState() {
    super.initState();
    for (final b in _beats) {
      _fetch(b);
    }
  }

  Future<void> _fetch(_DayBeat b) async {
    if (b.outlets != null || b.loading) return;
    setState(() => b.loading = true);
    try {
      final data = await Services.api.get('/api/v1/route-plan/customers',
          query: {'beat_id': b.id, 'date': fmtDate(widget.day), 'member': 'me'}) as Map<String, dynamic>;
      final rows = ((data['customers'] as List?) ?? []).cast<Map<String, dynamic>>()
        ..sort((a, c) => '${a['name']}'.toLowerCase().compareTo('${c['name']}'.toLowerCase()));
      if (!mounted) return;
      setState(() {
        b.outlets = rows;
        b.initial = {for (final r in rows) if (r['selected'] == true) r['id'] as int};
        // A beat unticked before this arrived stays unplanned (what was already visited cannot be).
        b.sel = b.removed ? b.visited : {...b.initial};
        b.removed = b.removed && b.sel.isEmpty;
      });
    } catch (_) {
      if (mounted) setState(() => b.outlets = const []);
    } finally {
      if (mounted) setState(() => b.loading = false);
    }
  }

  void _toggleBeat(_DayBeat b) {
    if (!b.canEdit) return;
    setState(() {
      if (b.value != false) {
        // Untick the whole beat: everything comes off (a visited outlet stays on the day).
        b.sel = b.visited;
        b.removed = b.sel.isEmpty;
      } else {
        b.removed = false;
        final all = b.outlets;
        if (all == null) {
          _fetch(b);
        } else {
          b.sel = {for (final o in all) o['id'] as int};
        }
      }
    });
  }

  void _toggleOutlet(_DayBeat b, int id, bool on) {
    if (!b.canEdit) return;
    setState(() {
      on ? b.sel.add(id) : b.sel.remove(id);
      b.removed = false;
    });
  }

  void _toggleOpen(_DayBeat b) {
    setState(() => b.open = !b.open);
    if (b.open) _fetch(b);
  }

  /// Save the ticks: a beat with nothing left ticked comes off the day, the others keep what is ticked.
  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final keep = <Map<String, dynamic>>[];
      final gone = <_DayBeat>[];
      for (final b in _beats.where((b) => b.changed)) {
        if ((b.outlets == null && b.removed) || (b.outlets != null && b.sel.isEmpty)) {
          gone.add(b);
        } else {
          keep.add({'beat_id': b.id, 'partner_ids': b.sel.toList()});
        }
      }
      for (final b in gone) {
        await Services.api.post('/api/v1/route-plan/days/remove', {
          'date': fmtDate(widget.day),
          'member': 'me',
          'beat_id': b.id,
          if (_entry(b.id)['id'] != null) 'plan_id': _entry(b.id)['id'],
        });
      }
      if (keep.isNotEmpty) {
        await Services.outbox.submit('/api/v1/route-plan/days', {
          'uuid': const Uuid().v4(),
          'date': fmtDate(widget.day),
          'member': 'me',
          'routes': keep,
        });
      }
      settleAndRefresh();
      if (!mounted) return;
      _saved = true;
      setState(() {
        _beats.removeWhere(gone.contains);
        for (final b in _beats) {
          b.initial = {...b.sel};
        }
      });
      showSnack(context, 'Plan saved');
    } catch (e) {
      if (mounted) showProblem(context, e is ApiException && e.status == 404 ? 'Please ask the office to switch this on.' : e.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// The + : an existing beat, whole or with some of its outlets.
  Future<void> _add() async {
    final planned = {for (final b in _beats) b.id};
    final picked = await Navigator.of(context).push<Map<int, List<int>>>(MaterialPageRoute(
      builder: (_) => AddExistingBeatScreen(
        day: widget.day,
        label: widget.label,
        routes: [for (final r in widget.routes) if (!planned.contains(r['id'])) r],
      ),
    ));
    if (picked == null || picked.isEmpty || !mounted) return;
    setState(() => _saving = true);
    try {
      await Services.outbox.submit('/api/v1/route-plan/days', {
        'uuid': const Uuid().v4(),
        'date': fmtDate(widget.day),
        'member': 'me',
        'routes': [for (final e in picked.entries) {'beat_id': e.key, 'partner_ids': e.value}],
      });
      settleAndRefresh();
      _saved = true;
      if (!mounted) return;
      setState(() {
        for (final id in picked.keys) {
          final b = _beatOf({'id': id, 'name': _route(id)['name']});
          _beats.add(_DayBeat(id: b.id, name: b.name, code: b.code, canEdit: !_past));
        }
        _beats.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      });
      for (final b in _beats) {
        _fetch(b);
      }
      showSnack(context, 'Added to ${fmtDate(widget.day)}');
    } catch (e) {
      if (mounted) showProblem(context, e.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<bool> _confirmDiscard() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('Discard changes?'),
        content: const Text('You unticked or ticked beats or outlets and did not save.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialog, false), child: const Text('Keep editing')),
          FilledButton(onPressed: () => Navigator.pop(dialog, true), child: const Text('Discard')),
        ],
      ),
    );
    return ok == true;
  }

  Widget _beatCard(_DayBeat b) {
    final planned = b.outlets == null ? null : b.sel.length;
    final line = _past
        ? [if (planned != null) '$planned outlet${planned == 1 ? '' : 's'} planned', 'view only'].join(' · ')
        : [
            if (planned != null) '$planned of ${b.outlets!.length} outlets planned',
            b.canEdit ? 'added by you' : 'assigned by manager',
          ].join(' · ');
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      clipBehavior: Clip.antiAlias,
      child: Column(children: [
        InkWell(
          onTap: () => _toggleOpen(b),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(4, 8, 10, 8),
            child: Row(children: [
              if (_past)
                const Padding(
                  padding: EdgeInsets.fromLTRB(14, 0, 12, 0),
                  child: Icon(Icons.event_available_rounded, color: AppColors.muted),
                )
              else
                Checkbox(
                  tristate: true,
                  value: b.value,
                  onChanged: (b.canEdit && !b.started) ? (_) => _toggleBeat(b) : null,
                ),
              Container(
                margin: const EdgeInsets.only(right: 10),
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                decoration: BoxDecoration(color: _blue.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
                child: Text(b.code, style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w900, color: _blue)),
              ),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(b.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14.5)),
                  Text(line, style: const TextStyle(fontSize: 12, color: AppColors.muted)),
                ]),
              ),
              if (!b.canEdit && !_past) const Padding(padding: EdgeInsets.only(right: 4), child: Icon(Icons.lock_rounded, size: 15, color: AppColors.muted)),
              Icon(b.open ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded, color: AppColors.muted),
            ]),
          ),
        ),
        if (b.open) ...[
          if (b.loading) const LinearProgressIndicator(minHeight: 2),
          if (!b.loading && (b.outlets ?? const []).isEmpty)
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 4, 16, 14),
              child: Align(alignment: Alignment.centerLeft, child: Text('No outlets in this beat yet.', style: TextStyle(color: AppColors.muted, fontSize: 12.5))),
            ),
          if (_past)
            for (final o in b.outlets ?? const <Map<String, dynamic>>[])
              if (b.initial.contains(o['id']))
                ListTile(
                  dense: true,
                  contentPadding: const EdgeInsets.only(left: 18, right: 14),
                  leading: const Icon(Icons.storefront_rounded, size: 20, color: AppColors.muted),
                  title: Text('${o['name']}', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5)),
                  subtitle: o['visited'] == true
                      ? const Text('Visited', style: TextStyle(fontSize: 11.5, color: AppColors.success))
                      : null,
                ),
          if (!_past)
            for (final o in b.outlets ?? const <Map<String, dynamic>>[])
              CheckboxListTile(
              dense: true,
              contentPadding: const EdgeInsets.only(left: 30, right: 14),
              controlAffinity: ListTileControlAffinity.leading,
              value: b.sel.contains(o['id']),
              // Once work has started on the beat, a planned outlet cannot be unticked (more can still be added).
              onChanged: (b.canEdit && o['visited'] != true && !(b.started && b.sel.contains(o['id'])))
                  ? (v) => _toggleOutlet(b, o['id'] as int, v == true)
                  : null,
              title: Text('${o['name']}', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5)),
              subtitle: o['visited'] == true ? const Text('Visited', style: TextStyle(fontSize: 11.5, color: AppColors.success)) : null,
              ),
          const SizedBox(height: 4),
        ],
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    final d = widget.day;
    final title = '${d.day.toString().padLeft(2, '0')} ${months[d.month - 1]} ${d.year}';
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (_dirty && !await _confirmDiscard()) return;
        if (mounted) Navigator.of(context).pop(_saved);
      },
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
            Text(_past ? 'View only: a day gone by cannot be changed' : 'Tick to plan, untick to unplan',
                style: const TextStyle(fontSize: 11.5, color: AppColors.muted, fontWeight: FontWeight.w500)),
          ]),
          actions: [
            if (!_past)
              IconButton(
                tooltip: 'Add an existing ${widget.label.toLowerCase()}',
                onPressed: _saving ? null : _add,
                icon: const Icon(Icons.add_circle_rounded, color: _blue, size: 30),
              ),
            const SizedBox(width: 6),
          ],
        ),
        bottomNavigationBar: _dirty
            ? SafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                  child: GradientButton(label: 'Save changes', icon: Icons.check_rounded, busy: _saving, onPressed: _saving ? null : _save),
                ),
              )
            : null,
        body: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 32), children: [
          if (_beats.isEmpty)
            Padding(
              padding: const EdgeInsets.all(24),
              child: Center(
                child: Text(_past ? 'No ${widget.label.toLowerCase()} was planned on this day.' : 'No ${widget.label.toLowerCase()} on this day. Tap + to add one.',
                    textAlign: TextAlign.center, style: const TextStyle(color: AppColors.muted)),
              ),
            ),
          for (final b in _beats) _beatCard(b),
        ]),
      ),
    );
  }
}


/// "Add an Existing Beat" as a full page. Each beat has a tick (the whole beat) and opens to its outlets, each
/// with a tick of its own: tick the beat to take it all, or open it and keep only the outlets wanted.
/// A beat still waiting for approval is greyed out. Returns `{beatId: [outletIds]}`.
class AddExistingBeatScreen extends StatefulWidget {
  const AddExistingBeatScreen({super.key, required this.day, required this.label, required this.routes});

  final DateTime day;
  final String label;
  final List<Map<String, dynamic>> routes;

  @override
  State<AddExistingBeatScreen> createState() => _AddExistingBeatScreenState();
}

class _AddExistingBeatScreenState extends State<AddExistingBeatScreen> {
  /// The outlets ticked in each beat; a beat with any ticked is chosen.
  final Map<int, Set<int>> _chosen = {};
  final Map<int, List<Map<String, dynamic>>> _outlets = {};
  final Set<int> _open = {};
  final Set<int> _loading = {};
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  static const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

  Future<void> _fetch(int id) async {
    if (_outlets.containsKey(id) || _loading.contains(id)) return;
    setState(() => _loading.add(id));
    try {
      final data = await Services.api.get('/api/v1/route-plan/customers',
          query: {'beat_id': id, 'date': fmtDate(widget.day), 'member': 'me'}) as Map<String, dynamic>;
      final rows = ((data['customers'] as List?) ?? []).cast<Map<String, dynamic>>()
        ..sort((a, c) => '${a['name']}'.toLowerCase().compareTo('${c['name']}'.toLowerCase()));
      if (mounted) setState(() => _outlets[id] = rows);
    } catch (_) {
      if (mounted) setState(() => _outlets[id] = const []);
    } finally {
      if (mounted) setState(() => _loading.remove(id));
    }
  }

  bool? _valueOf(int id) {
    final ticked = _chosen[id];
    if (ticked == null || ticked.isEmpty) return false;
    final all = _outlets[id];
    return all != null && ticked.length < all.length ? null : true;
  }

  /// The beat's tick: all of its outlets, or none.
  Future<void> _toggleBeat(int id) async {
    if (_valueOf(id) != false) {
      setState(() => _chosen.remove(id));
      return;
    }
    await _fetch(id);
    if (!mounted) return;
    setState(() => _chosen[id] = {for (final o in _outlets[id] ?? const <Map<String, dynamic>>[]) o['id'] as int});
  }

  void _toggleOutlet(int beat, int outlet, bool on) {
    setState(() {
      final set = _chosen.putIfAbsent(beat, () => {});
      on ? set.add(outlet) : set.remove(outlet);
      if (set.isEmpty) _chosen.remove(beat);
    });
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.day;
    final date = '${d.day.toString().padLeft(2, '0')} ${_months[d.month - 1]} ${d.year}';
    final needle = _search.text.trim().toLowerCase();
    final beats = [
      for (final r in widget.routes)
        // Only approved beats can be planned: one waiting for approval (new or edited) is not listed.
        if (r['approval_state'] != 'pending' &&
            (needle.isEmpty || '${r['name']} ${r['city'] ?? ''}'.toLowerCase().contains(needle))) r,
    ];
    // The order to choose from: 1) recurrent beats that repeat on this day (and a one-time beat for this very day),
    // 2) other recurrent beats that repeat on other days, 3) recurrent beats with no fixed days (Repeat: No), and
    // last any other one-time beat. Each group A to Z.
    final weekday = d.weekday - 1;
    final dayText = fmtDate(d);
    int rank(Map<String, dynamic> r) {
      final days = [for (final x in (r['weekdays'] as List?) ?? const []) (x as num).toInt()];
      if ('${r['schedule']}' == 'one_time') return '${r['date']}' == dayText ? 0 : 3;
      if (days.contains(weekday)) return 0;
      return days.isNotEmpty ? 1 : 2;
    }

    beats.sort((a, b) {
      final byRank = rank(a).compareTo(rank(b));
      return byRank != 0 ? byRank : '${a['name']}'.toLowerCase().compareTo('${b['name']}'.toLowerCase());
    });
    final outletCount = _chosen.values.fold<int>(0, (sum, s) => sum + s.length);
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Add an Existing ${widget.label}', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 19)),
          Text('For $date · tick a beat, or open it and tick outlets',
              style: const TextStyle(fontSize: 12, color: AppColors.muted, fontWeight: FontWeight.w500)),
        ]),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: GradientButton(
            label: 'Add selected ($outletCount outlet${outletCount == 1 ? '' : 's'} · ${_chosen.length} ${widget.label.toLowerCase()}${_chosen.length == 1 ? '' : 's'})',
            icon: Icons.check_rounded,
            onPressed: _chosen.isEmpty
                ? null
                : () => Navigator.pop(context, <int, List<int>>{for (final e in _chosen.entries) e.key: e.value.toList()}),
          ),
        ),
      ),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 16), children: [
        TextField(
          controller: _search,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            prefixIcon: const Icon(Icons.search_rounded, color: AppColors.muted),
            hintText: 'Search beat',
            filled: true,
            fillColor: Colors.white,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: AppColors.border)),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: AppColors.border)),
          ),
        ),
        const SizedBox(height: 10),
        if (beats.isEmpty)
          const Padding(padding: EdgeInsets.all(32), child: Center(child: Text('No beats to add.', style: TextStyle(color: AppColors.muted)))),
        for (final r in beats)
          Builder(builder: (_) {
            final id = r['id'] as int;
            final pending = '${r['approval_state']}' == 'pending';
            final open = _open.contains(id);
            final value = _valueOf(id);
            final line = pending
                ? 'Cannot be selected until approved'
                : [
                    if (value != false && _outlets[id] != null) '${_chosen[id]!.length} of ${_outlets[id]!.length} outlets',
                    if (value == false && r['customer_count'] != null) '${r['customer_count']} outlets',
                    if (asText(r['city']) != null) '${r['city']}',
                  ].join(' · ');
            return Opacity(
              opacity: pending ? 0.6 : 1,
              child: Container(
                margin: const EdgeInsets.only(bottom: 10),
                decoration: BoxDecoration(
                  color: pending ? AppColors.background : Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: value != false ? AppColors.primary : AppColors.border),
                ),
                child: Column(children: [
                  InkWell(
                    borderRadius: BorderRadius.circular(14),
                    onTap: pending
                        ? null
                        : () {
                            setState(() => open ? _open.remove(id) : _open.add(id));
                            if (!open) _fetch(id);
                          },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
                      child: Row(children: [
                        Checkbox(tristate: true, value: value, onChanged: pending ? null : (_) => _toggleBeat(id)),
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text('${r['name']}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14.5)),
                            if (line.isNotEmpty) Text(line, style: const TextStyle(fontSize: 12, color: AppColors.muted)),
                          ]),
                        ),
                        Container(
                          margin: const EdgeInsets.only(right: 4),
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: (pending ? AppColors.warning : AppColors.success).withValues(alpha: 0.14),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Text(pending ? 'Pending' : 'Approved',
                              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: pending ? AppColors.warning : AppColors.success)),
                        ),
                        if (!pending) Icon(open ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded, color: AppColors.muted),
                        const SizedBox(width: 4),
                      ]),
                    ),
                  ),
                  if (open) ...[
                    if (_loading.contains(id)) const LinearProgressIndicator(minHeight: 2),
                    if (!_loading.contains(id) && (_outlets[id] ?? const []).isEmpty)
                      const Padding(
                        padding: EdgeInsets.fromLTRB(16, 2, 16, 12),
                        child: Align(alignment: Alignment.centerLeft, child: Text('No outlets in this beat yet.', style: TextStyle(color: AppColors.muted, fontSize: 12.5))),
                      ),
                    for (final o in _outlets[id] ?? const <Map<String, dynamic>>[])
                      CheckboxListTile(
                        dense: true,
                        contentPadding: const EdgeInsets.only(left: 30, right: 14),
                        controlAffinity: ListTileControlAffinity.leading,
                        value: _chosen[id]?.contains(o['id']) ?? false,
                        onChanged: (v) => _toggleOutlet(id, o['id'] as int, v == true),
                        title: Text('${o['name']}', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5)),
                      ),
                    const SizedBox(height: 4),
                  ],
                ]),
              ),
            );
          }),
      ]),
    );
  }
}
