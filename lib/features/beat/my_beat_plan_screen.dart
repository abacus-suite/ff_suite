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
    final picked = await Navigator.of(context).push<List<int>>(
      MaterialPageRoute(builder: (_) => AddExistingBeatScreen(day: _day, label: _label, routes: _routes)),
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


/// A day's plan, opened by tapping a day: the beat(s) on it, a tick list of the existing beats, and below it
/// the outlets of the ticked beats.
class BeatDayScreen extends StatefulWidget {
  const BeatDayScreen(
      {super.key, required this.day, required this.label, required this.planned, required this.routes, this.entries = const []});

  final DateTime day;
  final String label;

  /// The day's plan lines from `/api/v1/route-plan/days`: `{date, beat, beat_code, added_by, ...}`. They say
  /// who put each beat on the day: a beat I added myself can be removed from the day, my manager's cannot.
  final List<Map<String, dynamic>> entries;

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

  /// Beats removed from this day here; the calendar reloads when the screen closes.
  final Set<int> _removed = {};
  bool _removing = false;

  /// Beats whose outlets are shown open under their card.
  final Set<int> _expanded = {};

  void _toggleOutlets(int id) {
    setState(() => _expanded.contains(id) ? _expanded.remove(id) : _expanded.add(id));
    if (_expanded.contains(id)) _fetch(id);
  }

  Map<String, dynamic> _entry(int id) => widget.entries
      .firstWhere((e) => (e['beat'] as Map?)?['id'] == id, orElse: () => <String, dynamic>{});

  Map<String, dynamic> _beat(int id) => _beats.firstWhere((b) => b['id'] == id, orElse: () => {'id': id});

  String _code(int id) => asText(_entry(id)['beat_code']) ?? asText(_beat(id)['code']) ?? _name(id);

  /// Put on this day by me (removable) or by my manager (not). The plan line says who added it;
  /// without that, who drew the beat decides.
  bool _addedByMe(int id) {
    final entry = _entry(id);
    if (entry['assigned_by_manager'] == true) return false;
    if (entry['added_by'] is Map) return beatIsMine({'added_by': entry['added_by']});
    return beatIsMine(_beat(id));
  }

  /// The bin: takes my own beat off this day only. The beat stays in My Beats.
  Future<void> _removeFromDay(int id) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: Text('Remove ${_name(id)}?'),
        content: const Text('It is taken off this day only. The beat stays in your beat list.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialog, false), child: const Text('Keep')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () => Navigator.pop(dialog, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _removing = true);
    try {
      final entry = _entry(id);
      await Services.api.post('/api/v1/route-plan/days/remove', {
        'date': fmtDate(widget.day),
        'member': 'me',
        'beat_id': id,
        if (entry['id'] != null) 'plan_id': entry['id'],
      });
      if (!mounted) return;
      setState(() {
        _removed.add(id);
        _ticked.remove(id);
      });
      settleAndRefresh();
      showSnack(context, 'Removed from this day. The beat stays in your beat list.');
    } catch (e) {
      if (!mounted) return;
      // Until the server has the call, say so plainly rather than a bare "not found".
      showProblem(
          context,
          e is ApiException && e.status == 404
              ? 'Removing a beat from a day is not switched on yet. Please ask the office.'
              : e.toString());
    } finally {
      if (mounted) setState(() => _removing = false);
    }
  }

  /// One of the day's beats: code, name, status and outlets, with the bin when I added it.
  Widget _dayBeatCard(int id) {
    final beat = _beat(id);
    final mine = _addedByMe(id);
    final pending = '${beat['approval_state']}' == 'pending';
    final count = (beat['customer_count'] as num?)?.toInt() ?? _outlets[id]?.length;
    final colour = pending ? AppColors.warning : AppColors.success;
    final open = _expanded.contains(id);
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => _toggleOutlets(id),
        child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 6, 6),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(
              margin: const EdgeInsets.only(right: 10),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(color: _blue.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
              child: Text(_code(id), style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w900, color: _blue)),
            ),
            Expanded(
              child: Text(_name(id),
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
            ),
            Container(
              margin: const EdgeInsets.only(right: 6),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(color: colour.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(14)),
              child: Text(pending ? 'Pending' : 'Approved',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: colour)),
            ),
            Icon(open ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded,
                size: 20, color: AppColors.muted),
            const SizedBox(width: 6),
          ]),
          Row(children: [
            Expanded(
              child: Text(
                  [if (count != null) '$count outlet${count == 1 ? '' : 's'}', mine ? 'added by you' : 'assigned by manager']
                      .join(' · '),
                  style: const TextStyle(fontSize: 12, color: AppColors.muted)),
            ),
            if (mine)
              IconButton(
                tooltip: 'Remove from this day',
                onPressed: _removing ? null : () => _removeFromDay(id),
                icon: const Icon(Icons.delete_outline_rounded, color: AppColors.danger),
              )
            else
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 8, vertical: 12),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.lock_rounded, size: 13, color: AppColors.muted),
                  SizedBox(width: 3),
                  Text('by manager', style: TextStyle(fontSize: 11.5, color: AppColors.muted)),
                ]),
              ),
          ]),
          if (open) ...[
            if (_loading.contains(id)) const LinearProgressIndicator(minHeight: 2),
            for (final c in _outlets[id] ?? const <Map<String, dynamic>>[])
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 4, 8, 4),
                child: Row(children: [
                  const Icon(Icons.storefront_rounded, size: 15, color: AppColors.muted),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text('${c['name']}',
                        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                  ),
                ]),
              ),
            if (!_loading.contains(id) && (_outlets[id] ?? const []).isEmpty)
              const Padding(
                padding: EdgeInsets.fromLTRB(4, 4, 8, 8),
                child: Text('No outlets in this beat yet.', style: TextStyle(fontSize: 12, color: AppColors.muted)),
              ),
            const SizedBox(height: 6),
          ],
        ]),
      ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    final d = widget.day;
    final title = '${d.day.toString().padLeft(2, '0')} ${months[d.month - 1]} ${d.year}';
    final ids = _ticked.toList();
    final first = ids.isEmpty ? null : _name(ids.first);
    final others = ids.skip(1).map(_name).toList();
    final onDay = [
      for (final b in widget.planned)
        if (!_removed.contains(b['id'])) b['id'] as int,
    ];
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) Navigator.of(context).pop(_removed.isNotEmpty);
      },
      child: Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
          const Text('Opened by tapping a day', style: TextStyle(fontSize: 11.5, color: AppColors.muted, fontWeight: FontWeight.w500)),
        ]),
      ),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 32), children: [
        for (final id in onDay) _dayBeatCard(id),
        if (onDay.isEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Text('No ${widget.label.toLowerCase()} on this day any more.',
                style: const TextStyle(color: AppColors.muted)),
          ),
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
                subtitle: Text(_code(id), style: const TextStyle(fontSize: 11.5)),
              ),
            ),
        if (ids.isNotEmpty)
          const Padding(
            padding: EdgeInsets.fromLTRB(4, 12, 4, 0),
            child: Text('… all outlets of the selected beats',
                style: TextStyle(fontSize: 11.5, fontStyle: FontStyle.italic, color: AppColors.muted)),
          ),
      ]),
      ),
    );
  }
}


/// "Add an Existing Beat" as a full page: every beat with a checkbox, more than one can be picked for the day.
/// A beat still waiting for approval is greyed out and cannot be ticked.
class AddExistingBeatScreen extends StatefulWidget {
  const AddExistingBeatScreen({super.key, required this.day, required this.label, required this.routes});

  final DateTime day;
  final String label;
  final List<Map<String, dynamic>> routes;

  @override
  State<AddExistingBeatScreen> createState() => _AddExistingBeatScreenState();
}

class _AddExistingBeatScreenState extends State<AddExistingBeatScreen> {
  final Set<int> _chosen = {};
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  static const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

  @override
  Widget build(BuildContext context) {
    final d = widget.day;
    final date = '${d.day.toString().padLeft(2, '0')} ${_months[d.month - 1]} ${d.year}';
    final needle = _search.text.trim().toLowerCase();
    final beats = [
      for (final r in widget.routes)
        if (needle.isEmpty || '${r['name']} ${r['city'] ?? ''}'.toLowerCase().contains(needle)) r,
    ];
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Add an Existing ${widget.label}', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 19)),
          Text('For $date · select one or more',
              style: const TextStyle(fontSize: 12, color: AppColors.muted, fontWeight: FontWeight.w500)),
        ]),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: GradientButton(
            label: 'Add selected beats (${_chosen.length})',
            icon: Icons.check_rounded,
            onPressed: _chosen.isEmpty ? null : () => Navigator.pop(context, _chosen.toList()),
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
          const Padding(padding: EdgeInsets.all(32), child: Center(child: Text('No beats found.', style: TextStyle(color: AppColors.muted)))),
        for (final r in beats)
          Builder(builder: (_) {
            final id = r['id'] as int;
            final pending = '${r['approval_state']}' == 'pending';
            final ticked = _chosen.contains(id);
            final line = pending
                ? 'Cannot be selected until approved'
                : [
                    if (r['customer_count'] != null) '${r['customer_count']} outlets',
                    if (asText(r['city']) != null) '${r['city']}',
                  ].join(' · ');
            return Opacity(
              opacity: pending ? 0.6 : 1,
              child: Container(
                margin: const EdgeInsets.only(bottom: 10),
                decoration: BoxDecoration(
                  color: pending ? AppColors.background : Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: ticked ? AppColors.primary : AppColors.border),
                ),
                child: InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: pending ? null : () => setState(() => ticked ? _chosen.remove(id) : _chosen.add(id)),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
                    child: Row(children: [
                      Checkbox(
                        value: ticked,
                        onChanged: pending ? null : (v) => setState(() => v == true ? _chosen.add(id) : _chosen.remove(id)),
                      ),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text('${r['name']}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14.5)),
                          if (line.isNotEmpty) Text(line, style: const TextStyle(fontSize: 12, color: AppColors.muted)),
                        ]),
                      ),
                      Container(
                        margin: const EdgeInsets.only(right: 8),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                        decoration: BoxDecoration(
                          color: (pending ? AppColors.warning : AppColors.success).withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Text(pending ? 'Pending approval' : 'Approved',
                            style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, color: pending ? AppColors.warning : AppColors.success)),
                      ),
                    ]),
                  ),
                ),
              ),
            );
          }),
      ]),
    );
  }
}
