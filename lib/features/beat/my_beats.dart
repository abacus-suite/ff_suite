import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show setEquals;
import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../core/services.dart';
import '../../core/theme.dart';
import '../../widgets/common.dart';
import 'beat_areas.dart';
import 'create_beat_screen.dart';

/// Beats edited on this phone and sent back for approval, with the day of the last edit: shown as
/// "Pending re-approval" while the server still has them waiting, and "edited 19 Oct" on the list.
class _EditedBeats {
  static String get _key => 'edited_beats_${Services.auth.profile?.employeeId ?? 0}';

  static Future<Map<int, String>> read() async {
    try {
      final raw = await Services.storage.read(_key);
      if (raw == null) return {};
      final saved = jsonDecode(raw);
      // Older saves were a plain list of ids.
      if (saved is List) return {for (final id in saved.whereType<int>()) id: ''};
      return (saved as Map).map((k, v) => MapEntry(int.parse('$k'), '$v'));
    } catch (_) {
      return {};
    }
  }

  static Future<void> add(int id) async {
    final edited = await read();
    edited[id] = fmtDate(DateTime.now());
    await Services.storage.write(_key, jsonEncode(edited.map((k, v) => MapEntry('$k', v))));
  }
}

const _wdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

/// "Mon, 2 Nov 2026" from a saved yyyy-mm-dd day.
String _niceDay(String iso) {
  final d = DateTime.tryParse(iso);
  return d == null ? iso : '${_wdays[d.weekday - 1]}, ${d.day} ${monthNames[d.month - 1].substring(0, 3)} ${d.year}';
}

/// Delete a beat I drew: the warning lists the days still planned on it, the request goes to the manager with
/// them, and once approved the beat is archived (its past plans and reports stay). True when something was sent.
Future<bool> deleteBeatFlow(BuildContext context, Map<String, dynamic> beat) async {
  final today = fmtDate(DateTime.now());
  var upcoming = <String>[];
  try {
    final data = await Services.api.get('/api/v1/beats/${beat['id']}/plans') as Map<String, dynamic>;
    upcoming = [
      for (final d in ((data['days'] as List?) ?? []).cast<Map<String, dynamic>>())
        if (d['status'] != 'done' && '${d['date']}'.compareTo(today) >= 0) '${d['date']}',
      for (final d in ((data['requested'] as List?) ?? [])) '$d',
    ]..sort();
  } catch (_) {}
  if (!context.mounted) return false;
  final ok = await showDialog<bool>(
    context: context,
    builder: (dialog) => AlertDialog(
      title: Text('Delete ${beat['name']}?'),
      content: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (upcoming.isEmpty)
            const Text('No upcoming day is planned on this beat.')
          else ...[
            Text('${upcoming.length} upcoming planned day${upcoming.length == 1 ? '' : 's'} will be removed once this is approved:',
                style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            for (final d in upcoming.take(12))
              Padding(padding: const EdgeInsets.only(bottom: 3), child: Text('•  ${_niceDay(d)}')),
            if (upcoming.length > 12) Text('…and ${upcoming.length - 12} more'),
          ],
          const SizedBox(height: 12),
          const Text(
              'Your request goes to your manager with these days. Once approved the beat is archived: you cannot use it '
              'again, but its past plans and reports stay.',
              style: TextStyle(fontSize: 12.5, color: AppColors.muted)),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(dialog, false), child: const Text('Keep it')),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
          onPressed: () => Navigator.pop(dialog, true),
          child: const Text('Send for approval'),
        ),
      ],
    ),
  );
  if (ok != true || !context.mounted) return false;
  try {
    final data = await Services.api.post('/api/v1/beats/${beat['id']}/delete', {}) as Map<String, dynamic>;
    settleAndRefresh();
    if (context.mounted) {
      showSnack(context, data['outcome'] == 'archived' ? '${beat['name']} deleted' : 'Sent to your manager for approval');
    }
    return true;
  } catch (e) {
    if (context.mounted) showProblem(context, e.toString());
    return false;
  }
}

/// "19 Oct" from a saved yyyy-mm-dd day.
String _shortDay(String day) {
  final d = DateTime.tryParse(day);
  return d == null ? '' : '${d.day} ${monthNames[d.month - 1].substring(0, 3)}';
}

/// My Beats: every beat I work, with its code, outlets and status. My own beats can be edited;
/// a beat my manager assigned is locked. Tapping a beat shows its outlets.
class MyBeatsList extends StatefulWidget {
  const MyBeatsList({super.key, required this.routes, required this.label, this.onChanged});

  /// The beats from `/api/v1/route-plan/routes`: `{id, name, code, approval_state, customer_count, added_by, ...}`.
  final List<Map<String, dynamic>> routes;
  final String label;

  /// Called after a beat was edited, so the list can be loaded again.
  final VoidCallback? onChanged;

  @override
  State<MyBeatsList> createState() => _MyBeatsListState();
}

/// Mine when I drew it; a beat drawn by somebody else was assigned to me by my manager.
bool beatIsMine(Map<String, dynamic> beat) {
  final by = beat['added_by'];
  if (by is! Map) return true;
  final profile = Services.auth.profile;
  return by['id'] == profile?.employeeId || '${by['name']}' == profile?.name;
}

class _MyBeatsListState extends State<MyBeatsList> {
  Map<int, String> _edited = {};

  @override
  void initState() {
    super.initState();
    _EditedBeats.read().then((ids) {
      if (mounted) setState(() => _edited = ids);
    });
  }

  Future<void> _open(Map<String, dynamic> beat) async {
    final changed = await Navigator.of(context).push<bool>(
        MaterialPageRoute(builder: (_) => BeatOutletsScreen(beat: beat, label: widget.label)));
    if (changed == true) _changed();
  }

  Future<void> _edit(Map<String, dynamic> beat) async {
    final changed =
        await Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) => CreateBeatScreen(existing: beat)));
    if (changed == true) _changed();
  }

  Future<void> _delete(Map<String, dynamic> beat) async {
    if (await deleteBeatFlow(context, beat)) _changed();
  }

  Future<void> _changed() async {
    final ids = await _EditedBeats.read();
    if (mounted) setState(() => _edited = ids);
    widget.onChanged?.call();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.routes.isEmpty) {
      return EmptyView(icon: Icons.alt_route_rounded, text: 'No ${widget.label.toLowerCase()}s yet.');
    }
    return Column(children: [for (final b in widget.routes) _tile(b)]);
  }

  Widget _tile(Map<String, dynamic> b) {
    final mine = beatIsMine(b);
    final pending = '${b['approval_state']}' == 'pending';
    final editedOn = _edited[b['id']];
    final reapproval = pending && editedOn != null;
    final deleting = b['delete_requested'] == true;
    final count = (b['customer_count'] as num?)?.toInt();
    final line = [
      if (count != null) '$count outlet${count == 1 ? '' : 's'}',
      if (!mine)
        'assigned by manager'
      else if (editedOn != null && _shortDay(editedOn).isNotEmpty)
        'edited ${_shortDay(editedOn)}'
      else
        'created by you',
      // A one-time beat is for its day only: it leaves the list after it.
      if (_shortDay('${b['expires'] ?? ''}').isNotEmpty) 'expires ${_shortDay('${b['expires']}')}',
    ].join(' · ');
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => _open(b),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 8, 8),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              if (asText(b['code']) != null)
                Container(
                  margin: const EdgeInsets.only(right: 10),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
                  child: Text('${b['code']}',
                      style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w900, color: AppColors.primary)),
                ),
              Expanded(
                child: Text('${b['name']}',
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14.5)),
              ),
              const SizedBox(width: 6),
              // Capped, so a long status never squeezes the name off a small phone.
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 128),
                child: FittedBox(fit: BoxFit.scaleDown, child: _status(pending, reapproval, deleting: deleting)),
              ),
            ]),
            const SizedBox(height: 4),
            Row(children: [
              Expanded(child: Text(line, style: const TextStyle(fontSize: 12, color: AppColors.muted))),
              if (mine && !deleting) ...[
                IconButton(
                  tooltip: 'Edit',
                  visualDensity: VisualDensity.compact,
                  onPressed: () => _edit(b),
                  icon: const Icon(Icons.edit_rounded, size: 19, color: AppColors.primary),
                ),
                IconButton(
                  tooltip: 'Delete',
                  visualDensity: VisualDensity.compact,
                  onPressed: () => _delete(b),
                  icon: const Icon(Icons.delete_outline_rounded, size: 20, color: AppColors.danger),
                ),
              ] else if (mine)
                const SizedBox.shrink()
              else
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.lock_rounded, size: 13, color: AppColors.muted),
                    SizedBox(width: 3),
                    Text('by manager', style: TextStyle(fontSize: 11.5, color: AppColors.muted)),
                  ]),
                ),
            ]),
          ]),
        ),
      ),
    );
  }

  Widget _status(bool pending, bool reapproval, {bool deleting = false}) {
    final colour = pending || deleting ? AppColors.warning : AppColors.success;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: colour.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(14)),
      child: Text(deleting ? 'Deletion pending' : (reapproval ? 'Pending re-approval' : (pending ? 'Pending approval' : 'Approved')),
          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: colour)),
    );
  }
}

/// A beat's outlets, opened by tapping it in My Beats. My own beat has the pencil to edit it.
class BeatOutletsScreen extends StatefulWidget {
  const BeatOutletsScreen({super.key, required this.beat, required this.label});

  final Map<String, dynamic> beat;
  final String label;

  @override
  State<BeatOutletsScreen> createState() => _BeatOutletsScreenState();
}

class _BeatOutletsScreenState extends State<BeatOutletsScreen> {
  List<Map<String, dynamic>> _outlets = [];
  bool _loading = true;
  String? _error;
  bool _changed = false;

  /// Outlets (0) or the plan dates of the beat (1).
  int _tab = 0;
  Map<String, dynamic>? _plans;
  bool _plansLoading = false;
  String? _plansError;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _loadPlans() async {
    setState(() {
      _plansLoading = true;
      _plansError = null;
    });
    try {
      final data = await Services.api.get('/api/v1/beats/${widget.beat['id']}/plans') as Map<String, dynamic>;
      if (mounted) setState(() => _plans = data);
    } catch (e) {
      if (mounted) setState(() => _plansError = e.toString());
    } finally {
      if (mounted) setState(() => _plansLoading = false);
    }
  }

  /// Completed, Planned or Missed on the Plan dates tab.
  int _planTab = 1;

  /// Planned days ticked to be taken off the plan.
  final Set<String> _unplanSel = {};
  bool _unplanning = false;

  Widget _tabs() {
    Widget half(String text, int index) {
      final on = _tab == index;
      return Expanded(
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () {
            setState(() => _tab = index);
            if (index == 2 && _plans == null && !_plansLoading) _loadPlans();
          },
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 9),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: on ? AppColors.primary.withValues(alpha: 0.12) : Colors.transparent,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(text,
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5, color: on ? AppColors.primary : AppColors.text)),
          ),
        ),
      );
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(23),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(children: [half('Details', 0), half('Outlets', 1), half('Plan dates', 2)]),
    );
  }

  /// Take planned days off the plan: no approval needed.
  Future<void> _unplan({List<String>? dates}) async {
    final all = dates == null;
    final count = dates?.length ?? _plannedDays().length;
    if (count == 0) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: Text(all ? 'Unplan all $count days?' : 'Unplan $count day${count == 1 ? '' : 's'}?'),
        content: const Text('These days are taken off the plan now. No approval is needed, and the beat itself stays.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialog, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(dialog, true), child: const Text('Unplan')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _unplanning = true);
    try {
      await Services.api.post('/api/v1/beats/${widget.beat['id']}/unplan', {if (all) 'all': true else 'dates': dates});
      _changed = true;
      _unplanSel.clear();
      settleAndRefresh();
      await _loadPlans();
      if (mounted) showSnack(context, 'Taken off the plan');
    } catch (e) {
      if (mounted) showProblem(context, e.toString());
    } finally {
      if (mounted) setState(() => _unplanning = false);
    }
  }

  List<Map<String, dynamic>> _daysOf(bool Function(Map<String, dynamic> d, String today) test) {
    final today = fmtDate(DateTime.now());
    final days = ((_plans?['days'] as List?) ?? []).cast<Map<String, dynamic>>();
    return [for (final d in days) if (test(d, today)) d];
  }

  List<Map<String, dynamic>> _plannedDays() => _daysOf((d, today) => d['status'] != 'done' && '${d['date']}'.compareTo(today) >= 0)
    ..sort((a, b) => '${a['date']}'.compareTo('${b['date']}'));

  /// The plan dates of this beat in three tabs: Completed, Planned (days can be taken off) and Missed.
  List<Widget> _planRows() {
    final data = _plans;
    if (data == null) return const [];
    final done = _daysOf((d, today) => d['status'] == 'done');
    final planned = _plannedDays();
    final missed = _daysOf((d, today) => d['status'] != 'done' && '${d['date']}'.compareTo(today) < 0);
    final requested = ((data['requested'] as List?) ?? []).map((e) => '$e').toList();
    final canUnplan = beatIsMine(widget.beat) && widget.beat['delete_requested'] != true;

    String counts(Map<String, dynamic> d) => '${d['completed_count'] ?? 0} of ${d['planned_count'] ?? 0} outlets visited';

    Widget chip(String text, int index, int n, Color colour) {
      final on = _planTab == index;
      return Expanded(
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => setState(() => _planTab = index),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 9),
            margin: const EdgeInsets.symmetric(horizontal: 3),
            decoration: BoxDecoration(
              color: on ? colour.withValues(alpha: 0.14) : Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: on ? colour : AppColors.border),
            ),
            child: Column(children: [
              Text('$n', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: colour)),
              Text(text, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12, color: on ? colour : AppColors.muted)),
            ]),
          ),
        ),
      );
    }

    Widget row(Map<String, dynamic> d, String note, Color colour, IconData icon) => Card(
          margin: const EdgeInsets.only(bottom: 8),
          child: ListTile(
            dense: true,
            leading: Icon(icon, color: colour),
            title: Text(_niceDay('${d['date']}'), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
            subtitle: Text(note, style: const TextStyle(fontSize: 12)),
          ),
        );

    final body = <Widget>[];
    if (_planTab == 0) {
      body.addAll([for (final d in done) row(d, counts(d), AppColors.success, Icons.check_circle_rounded)]);
      if (done.isEmpty) body.add(const EmptyView(icon: Icons.check_circle_outline_rounded, text: 'Nothing completed on this beat yet.'));
    } else if (_planTab == 2) {
      body.addAll([for (final d in missed) row(d, counts(d), AppColors.danger, Icons.event_busy_rounded)]);
      if (missed.isEmpty) body.add(const EmptyView(icon: Icons.event_available_rounded, text: 'No missed days.'));
    } else {
      final dates = [for (final d in planned) '${d['date']}'];
      final picked = _unplanSel.where(dates.contains).toList();
      if (canUnplan && planned.isNotEmpty) {
        body.add(Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(children: [
            TextButton(
              onPressed: () => setState(() {
                if (picked.length == dates.length) {
                  _unplanSel.clear();
                } else {
                  _unplanSel
                    ..clear()
                    ..addAll(dates);
                }
              }),
              child: Text(picked.length == dates.length ? 'Clear' : 'Select all'),
            ),
            const Spacer(),
            if (picked.isNotEmpty)
              FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
                onPressed: _unplanning ? null : () => _unplan(dates: picked),
                icon: const Icon(Icons.event_busy_rounded, size: 18),
                label: Text('Unplan (${picked.length})'),
              ),
            if (picked.isEmpty)
              OutlinedButton.icon(
                onPressed: _unplanning ? null : () => _unplan(),
                icon: const Icon(Icons.event_busy_rounded, size: 18),
                label: const Text('Unplan all'),
              ),
          ]),
        ));
      }
      for (final d in planned) {
        final date = '${d['date']}';
        final note = d['status'] == 'in_progress' ? 'In progress · ${counts(d)}' : '${d['planned_count'] ?? 0} outlets planned';
        body.add(canUnplan
            ? Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: CheckboxListTile(
                  dense: true,
                  controlAffinity: ListTileControlAffinity.leading,
                  value: _unplanSel.contains(date),
                  onChanged: (v) => setState(() => v == true ? _unplanSel.add(date) : _unplanSel.remove(date)),
                  title: Text(_niceDay(date), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
                  subtitle: Text(note, style: const TextStyle(fontSize: 12)),
                ),
              )
            : row(d, note, AppColors.primary, Icons.event_rounded));
      }
      for (final iso in requested) {
        body.add(row({'date': iso}, 'Waiting for approval · planned once approved', AppColors.warning, Icons.hourglass_top_rounded));
      }
      if (planned.isEmpty && requested.isEmpty) {
        body.add(const EmptyView(icon: Icons.event_rounded, text: 'No upcoming day is planned on this beat.'));
      }
    }

    return [
      Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Row(children: [
          chip('Completed', 0, done.length, AppColors.success),
          chip('Planned', 1, planned.length + requested.length, AppColors.primary),
          chip('Missed', 2, missed.length, AppColors.danger),
        ]),
      ),
      ...body,
    ];
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await Services.api.get('/api/v1/route-plan/customers',
          query: {'beat_id': widget.beat['id'], 'date': fmtDate(DateTime.now()), 'member': 'me'}) as Map<String, dynamic>;
      if (mounted) {
        final list = ((data['customers'] as List?) ?? []).cast<Map<String, dynamic>>().toList()
          ..sort((a, b) => (a['name'] ?? '').toString().toLowerCase().compareTo((b['name'] ?? '').toString().toLowerCase()));
        setState(() => _outlets = list);
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _delete() async {
    if (await deleteBeatFlow(context, widget.beat) && mounted) Navigator.of(context).pop(true);
  }

  Future<void> _edit() async {
    final saved = await Navigator.of(context)
        .push<bool>(MaterialPageRoute(builder: (_) => CreateBeatScreen(existing: widget.beat, existingOutlets: _outlets)));
    if (saved == true) {
      _changed = true;
      await _load();
    }
  }

  /// What the beat is: its territory and areas, one time or recurrent, and the day or weekdays it is for.
  Widget _info() {
    final b = widget.beat;
    final oneTime = '${b['schedule']}' == 'one_time';
    final days = [for (final d in (b['weekdays'] as List?) ?? const []) _wdays[(d as num).toInt() % 7]];
    final areas = [for (final a in (b['areas'] as List?) ?? const []) '${(a as Map)['name']}'];
    final planned = [for (final d in (b['plan_dates'] as List?) ?? const []) _niceDay('$d')];
    Widget line(String label, String value) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 5),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SizedBox(width: 96, child: Text(label, style: const TextStyle(fontSize: 12.5, color: AppColors.muted))),
            Expanded(
              child: Text(value.isEmpty ? '—' : value,
                  textAlign: TextAlign.right, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
            ),
          ]),
        );
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
      decoration: BoxDecoration(
          color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.border)),
      child: Column(children: [
        line('Beat', '${b['name']}'),
        line('Code', asText(b['code']) ?? ''),
        line('Status', '${b['approval_state']}' == 'pending' ? 'Pending approval' : 'Approved'),
        line('Outlets', '${_loading ? (b['customer_count'] ?? 0) : _outlets.length}'),
        line('Region', asText(b['region'] is Map ? (b['region'] as Map)['name'] : b['region']) ?? ''),
        line('District / Territory',
            asText(b['territory'] is Map ? (b['territory'] as Map)['name'] : b['territory']) ?? asText(b['city']) ?? ''),
        line('Area', areas.join(', ')),
        line('Schedule', oneTime ? 'One time' : 'Recurrent'),
        if (oneTime) line('Day', _niceDay('${b['date'] ?? ''}')),
        if (!oneTime) line('Repeat on', days.isEmpty ? 'Does not repeat' : days.join(', ')),
        if (!oneTime && days.isEmpty && planned.isNotEmpty) line('Planned days', planned.join(', ')),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final b = widget.beat;
    final pending = '${b['approval_state']}' == 'pending';
    final sub = [
      if (asText(b['code']) != null) '${b['code']}',
      '${_loading ? (b['customer_count'] ?? 0) : _outlets.length} outlets',
      pending ? 'Pending approval' : 'Approved',
    ].join(' · ');
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) Navigator.of(context).pop(_changed);
      },
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${b['name']}', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
            Text(sub, style: const TextStyle(fontSize: 11.5, color: AppColors.muted, fontWeight: FontWeight.w500)),
          ]),
          actions: [
            if (beatIsMine(b) && b['delete_requested'] != true) ...[
              IconButton(tooltip: 'Edit', onPressed: _edit, icon: const Icon(Icons.edit_rounded, color: AppColors.primary)),
              IconButton(
                tooltip: 'Delete',
                onPressed: _delete,
                icon: const Icon(Icons.delete_outline_rounded, color: AppColors.danger),
              ),
            ],
          ],
        ),
        body: RefreshIndicator(
          onRefresh: () async {
            await _load();
            if (_tab == 2) await _loadPlans();
          },
          child: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 32), children: [
            _tabs(),
            if (_tab == 0) _info(),
            if (_tab == 2) ...[
              if (_plansLoading) const LinearProgressIndicator(minHeight: 2),
              if (_plansError != null) ErrorView(message: _plansError!, onRetry: _loadPlans),
              ..._planRows(),
            ],
            if (_tab == 1) ...[
            if (_loading) const LinearProgressIndicator(minHeight: 2),
            if (_error != null) ErrorView(message: _error!, onRetry: _load),
            if (!_loading && _error == null && _outlets.isEmpty)
              const EmptyView(icon: Icons.storefront_rounded, text: 'No outlets on this beat yet.'),
            for (final c in _outlets)
              Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  title: Text('${c['name']}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
                  subtitle: Text(
                    [
                      asText((c['district'] as Map?)?['name']) ?? asText(c['city']) ?? asText(c['address']),
                      _kind(c),
                    ].whereType<String>().join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
              ),
            ],
          ]),
        ),
      ),
    );
  }

  static String? _kind(Map<String, dynamic> c) {
    final kind = asText(c['category_type']);
    if (kind == null) return null;
    return '${kind[0].toUpperCase()}${kind.substring(1)}';
  }
}

/// Edit Beat: the weekdays it repeats on, and its outlets (any can be taken off, more can be added).
/// After saving, the beat goes to the manager for approval again.
class EditBeatScreen extends StatefulWidget {
  const EditBeatScreen({super.key, required this.beat, this.outlets});

  final Map<String, dynamic> beat;

  /// The beat's outlets when already loaded; fetched here otherwise.
  final List<Map<String, dynamic>>? outlets;

  @override
  State<EditBeatScreen> createState() => _EditBeatScreenState();
}

class _EditBeatScreenState extends State<EditBeatScreen> {
  static const _dayNames = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

  /// The outlets on the beat as saved, and as ticked now.
  Set<int> _onBeat = {};
  Set<int> _chosen = {};

  /// Every outlet seen so far (the beat's own, and what the search found), by id.
  final Map<int, Map<String, dynamic>> _known = {};

  /// One time or recurrent, as saved and as set now; a one-time beat's day.
  late final String _schedule0 = '${widget.beat['schedule']}' == 'one_time' ? 'one_time' : 'recurrent';
  late String _schedule = _schedule0;
  late final DateTime? _date0 = DateTime.tryParse('${widget.beat['date'] ?? ''}');
  late DateTime _date = DateUtils.dateOnly(_date0 ?? DateTime.now());

  /// The areas of the beat, as saved and as set now, and the territory's areas to choose from.
  late final Set<int> _areas0 = {for (final a in (widget.beat['area_ids'] as List?) ?? const []) (a as num).toInt()};
  late final Set<int> _areas = {..._areas0};
  List<Map<String, dynamic>> _territoryAreas = [];
  bool _loading = true;
  bool _busy = false;

  /// Repeat on: as saved (with its days), and as set now.
  late final List<int> _days0 = [for (final d in (widget.beat['weekdays'] as List?) ?? const []) (d as num).toInt()];
  late final bool _repeat0 = _days0.isNotEmpty;
  late bool _repeat = _repeat0;
  late final Set<int> _days = {..._days0};

  bool get _canRepeat => _schedule == 'recurrent';
  bool get _repeatChanged => _repeat != _repeat0 || (_repeat && !setEquals(_days, {..._days0}));
  bool get _dateChanged =>
      _schedule == 'one_time' && (_date0 == null || _date != DateUtils.dateOnly(_date0));
  bool get _dirty =>
      !setEquals(_chosen, _onBeat) ||
      _schedule != _schedule0 ||
      _dateChanged ||
      !setEquals(_areas, _areas0) ||
      (_schedule == 'recurrent' && _repeatChanged);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      var outlets = widget.outlets;
      if (outlets == null) {
        final data = await Services.api.get('/api/v1/route-plan/customers',
            query: {'beat_id': widget.beat['id'], 'date': fmtDate(DateTime.now()), 'member': 'me'}) as Map<String, dynamic>;
        outlets = ((data['customers'] as List?) ?? []).cast<Map<String, dynamic>>();
      }
      // The areas of the beat's territory, to add or take off.
      var areas = <Map<String, dynamic>>[];
      try {
        final list = await Services.api.get('/api/v1/territories') as List;
        final territory = list.cast<Map<String, dynamic>>().where((t) => t['id'] == widget.beat['territory_id']).firstOrNull;
        areas = ((territory?['areas'] as List?) ?? const []).cast<Map<String, dynamic>>();
      } catch (_) {}
      // Whatever the beat already has stays in the list, even when the territory list could not be read.
      for (final a in ((widget.beat['areas'] as List?) ?? const []).cast<Map>()) {
        if (!areas.any((x) => x['id'] == a['id'])) areas = [...areas, a.cast<String, dynamic>()];
      }
      if (!mounted) return;
      setState(() {
        _onBeat = {for (final o in outlets!) o['id'] as int};
        _chosen = {..._onBeat};
        for (final o in outlets) {
          _known[o['id'] as int] = o;
        }
        _territoryAreas = areas;
      });
    } catch (e) {
      if (mounted) showProblem(context, e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// The outlets of the beat's own territory (district), found by the server: all of them, or those matching what
  /// was typed.
  Future<List<Map<String, dynamic>>> _search(String q) async {
    final res = await Services.api.get('/api/v1/clients', query: {
      if (widget.beat['territory_id'] != null) 'territory_id': widget.beat['territory_id'],
      'exclude_leads': 1,
      'limit': 100,
      if (q.isNotEmpty) 'q': q,
    });
    final list = res is Map ? (res['clients'] as List? ?? []) : (res as List? ?? []);
    return list.cast<Map<String, dynamic>>();
  }

  /// Tick the outlets that stay and tick new ones: the beat's own outlets first, then the territory's, searched on
  /// the server as you type.
  Future<void> _pickOutlets() async {
    final picked = Set<int>.from(_chosen);
    var query = '';
    var results = <Map<String, dynamic>>[];
    var searching = true;
    var started = false;
    Timer? timer;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheet) {
        return StatefulBuilder(builder: (context, setSheet) {
          Future<void> run(String q) async {
            try {
              final found = await _search(q);
              for (final c in found) {
                _known[c['id'] as int] = c;
              }
              if (context.mounted && q == query.trim()) {
                setSheet(() {
                  results = found;
                  searching = false;
                });
              }
            } catch (_) {
              if (context.mounted) setSheet(() => searching = false);
            }
          }

          if (!started) {
            started = true;
            WidgetsBinding.instance.addPostFrameCallback((_) => run(''));
          }
          // No search yet: what is ticked comes first, so it is easy to see and take off.
          final ticked = <Map<String, dynamic>>[];
          for (final id in picked) {
            final known = _known[id];
            if (known != null) ticked.add(known);
          }
          ticked.sort((a, b) => '${a['name']}'.toLowerCase().compareTo('${b['name']}'.toLowerCase()));
          final rows = query.trim().isEmpty
              ? [...ticked, ...results.where((c) => !picked.contains(c['id']))]
              : results;
          return SafeArea(
            child: SizedBox(
              height: MediaQuery.of(context).size.height * 0.75,
              child: Column(children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: TextField(
                    onChanged: (v) {
                      query = v;
                      timer?.cancel();
                      setSheet(() => searching = true);
                      timer = Timer(const Duration(milliseconds: 350), () => run(v.trim()));
                    },
                    decoration: const InputDecoration(
                        prefixIcon: Icon(Icons.search_rounded), hintText: 'Search outlet…', isDense: true),
                  ),
                ),
                if (searching) const LinearProgressIndicator(minHeight: 2),
                Expanded(
                  child: rows.isEmpty && !searching
                      ? const Center(child: Text('No outlet found', style: TextStyle(color: AppColors.muted)))
                      : ListView.builder(
                          itemCount: rows.length,
                          itemBuilder: (_, i) {
                            final c = rows[i];
                            final id = c['id'] as int;
                            return CheckboxListTile(
                              value: picked.contains(id),
                              onChanged: (v) => setSheet(() => v == true ? picked.add(id) : picked.remove(id)),
                              controlAffinity: ListTileControlAffinity.leading,
                              title: Text('${c['name']}', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                              subtitle: Text(_onBeat.contains(id) ? 'On this beat' : '${c['city'] ?? c['address'] ?? ''}',
                                  style: const TextStyle(fontSize: 12)),
                            );
                          },
                        ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                  child: SizedBox(
                    width: double.infinity,
                    child: FilledButton(onPressed: () => Navigator.pop(sheet), child: Text('Done (${picked.length} selected)')),
                  ),
                ),
              ]),
            ),
          );
        });
      },
    );
    timer?.cancel();
    if (mounted) setState(() => _chosen = picked);
  }

  Future<void> _pickAreas() async {
    final picked = await pickBeatAreas(context, _territoryAreas, _areas);
    if (picked != null && mounted) {
      setState(() {
        _areas
          ..clear()
          ..addAll(picked);
      });
    }
  }

  Future<void> _pickDate() async {
    final today = DateUtils.dateOnly(DateTime.now());
    final picked = await showDatePicker(
      context: context,
      initialDate: _date.isBefore(today) ? today : _date,
      firstDate: today,
      lastDate: today.add(const Duration(days: 365)),
    );
    if (picked != null && mounted) setState(() => _date = DateUtils.dateOnly(picked));
  }

  void _setSchedule(String value) {
    if (value == _schedule) return;
    setState(() {
      _schedule = value;
      // Back to recurrent from a one-time beat: repeat on its weekdays, to be chosen.
      if (value == 'recurrent' && _schedule0 == 'one_time') _repeat = true;
    });
  }

  /// Repeat on with no day left ticked: the repeat will be switched off, so ask first.
  Future<bool> _confirmRepeatOff() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('Switch repeat off?'),
        content: const Text(
            'No day is selected, so this beat will stop repeating (repeat mode off). You can switch it on again later by '
            'opening the beat and choosing days. Do you want to continue?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialog, false), child: const Text('No, choose days')),
          FilledButton(onPressed: () => Navigator.pop(dialog, true), child: const Text('Yes, switch off')),
        ],
      ),
    );
    return ok == true;
  }

  Future<void> _save() async {
    if (_chosen.isEmpty) {
      showProblem(context, 'Keep at least one outlet on the beat.');
      return;
    }
    if (_schedule == 'one_time' && _date.isBefore(DateUtils.dateOnly(DateTime.now())) && _dateChanged) {
      showProblem(context, 'Choose today or a later day for this one-time beat.');
      return;
    }
    if (_schedule == 'recurrent' && _repeat && _days.isEmpty) {
      if (!await _confirmRepeatOff() || !mounted) return;
      setState(() => _repeat = false);
    }
    setState(() => _busy = true);
    try {
      final toRecurrent = _schedule == 'recurrent' && _schedule0 == 'one_time';
      await Services.api.post('/api/v1/beats/${widget.beat['id']}/update', {
        'partner_ids': _chosen.toList(),
        'schedule': _schedule,
        if (_schedule == 'one_time') 'date': fmtDate(_date),
        if (_schedule == 'recurrent' && (_repeatChanged || toRecurrent)) 'repeat': _repeat,
        if (_schedule == 'recurrent' && (_repeatChanged || toRecurrent))
          'weekdays': _repeat ? (_days.toList()..sort()) : <int>[],
        if (!setEquals(_areas, _areas0)) 'area_ids': _areas.toList(),
      });
      await _EditedBeats.add(widget.beat['id'] as int);
      settleAndRefresh();
      if (!mounted) return;
      showSnack(context, 'Sent to your manager for approval');
      Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) showProblem(context, e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final b = widget.beat;
    final territory = asText(b['city']) ?? asText((b['territory'] as Map?)?['name']) ?? '—';
    final added = _chosen.difference(_onBeat).length;
    final removed = _onBeat.difference(_chosen).length;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Edit Beat', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
          Text(asText(b['code']) ?? '${b['name']}',
              style: const TextStyle(fontSize: 11.5, color: AppColors.muted, fontWeight: FontWeight.w500)),
        ]),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 14),
          child: GradientButton(
            label: 'Save – send for approval',
            busy: _busy,
            onPressed: _loading || _busy || !_dirty ? null : _save,
          ),
        ),
      ),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 24), children: [
        if (asText(b['region'] is Map ? (b['region'] as Map)['name'] : b['region']) != null) ...[
          _label('Region'),
          _field(asText(b['region'] is Map ? (b['region'] as Map)['name'] : b['region'])!, locked: true),
          const SizedBox(height: 16),
        ],
        _label('District / Territory'),
        _field(territory, locked: true),
        const SizedBox(height: 16),
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Text('Area', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5)),
        ),
        BeatAreaField(
          names: [for (final a in _territoryAreas) if (_areas.contains(a['id'])) '${a['name']}'],
          onChange: _pickAreas,
          enabled: !_loading,
        ),
        const SizedBox(height: 16),
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Text('Schedule', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5)),
        ),
        Row(children: [
          for (final (value, text) in const [('recurrent', 'Recurrent'), ('one_time', 'One time')])
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                label: Text(text, style: const TextStyle(fontWeight: FontWeight.w700)),
                selected: _schedule == value,
                onSelected: (_) => _setSchedule(value),
              ),
            ),
        ]),
        const SizedBox(height: 16),
        if (_schedule == 'one_time') ...[
          _label('Day'),
          _field(_niceDay(_date.toIso8601String().substring(0, 10)), onTap: _pickDate),
          const SizedBox(height: 16),
        ],
        if (_canRepeat) ...[
          _label('Repeat on?'),
          Container(
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: AppColors.border),
            ),
            child: Row(children: [
              for (final (text, on) in const [('Yes', true), ('No', false)])
                Expanded(
                  child: InkWell(
                    borderRadius: BorderRadius.circular(21),
                    onTap: () => setState(() => _repeat = on),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 11),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: _repeat == on ? AppColors.primary : Colors.transparent,
                        borderRadius: BorderRadius.circular(21),
                      ),
                      child: Text(text,
                          style: TextStyle(fontWeight: FontWeight.w800, color: _repeat == on ? Colors.white : AppColors.text)),
                    ),
                  ),
                ),
            ]),
          ),
          if (_repeat) ...[
            const SizedBox(height: 14),
            Text('Repeat on', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5)),
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (var i = 0; i < 7; i++)
                FilterChip(
                  label: Text(_dayNames[i], style: const TextStyle(fontWeight: FontWeight.w700)),
                  selected: _days.contains(i),
                  onSelected: (on) => setState(() => on ? _days.add(i) : _days.remove(i)),
                ),
            ]),
          ] else
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text('Repeat is off: the beat stays in your list without fixed days.',
                  style: TextStyle(fontSize: 12, color: AppColors.muted)),
            ),
          const SizedBox(height: 16),
        ],
        _label('Outlets'),
        _field(
          _loading
              ? 'Loading outlets…'
              : '${_chosen.length} outlet${_chosen.length == 1 ? '' : 's'} selected'
                  '${added == 0 && removed == 0 ? '' : ' ($added added, $removed removed)'}',
          onTap: _loading ? null : _pickOutlets,
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.warning.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.warning.withValues(alpha: 0.35)),
          ),
          child: const Text(
              'After you save, the beat goes to your manager for approval again. Till then it shows "Pending re-approval".',
              style: TextStyle(fontSize: 12.5, color: Color(0xFF9A3412))),
        ),
      ]),
    );
  }

  Widget _label(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text.rich(TextSpan(text: text, children: const [
          TextSpan(text: ' *', style: TextStyle(color: AppColors.danger)),
        ]), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5)),
      );

  Widget _field(String text, {bool locked = false, VoidCallback? onTap}) => InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          decoration: BoxDecoration(
            color: locked ? AppColors.background : Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(children: [
            Expanded(child: Text(text, style: TextStyle(fontSize: 14, color: locked ? AppColors.muted : AppColors.text))),
            Icon(locked ? Icons.lock_outline_rounded : Icons.keyboard_arrow_down_rounded, color: AppColors.muted, size: 20),
          ]),
        ),
      );
}
