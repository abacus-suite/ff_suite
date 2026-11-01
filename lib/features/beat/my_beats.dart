import 'dart:convert';

import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../core/services.dart';
import '../../core/theme.dart';
import '../../widgets/common.dart';

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
        await Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) => EditBeatScreen(beat: beat)));
    if (changed == true) _changed();
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
    final count = (b['customer_count'] as num?)?.toInt();
    final line = [
      if (count != null) '$count outlet${count == 1 ? '' : 's'}',
      if (!mine)
        'assigned by manager'
      else if (editedOn != null && _shortDay(editedOn).isNotEmpty)
        'edited ${_shortDay(editedOn)}'
      else
        'created by you',
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
                child: FittedBox(fit: BoxFit.scaleDown, child: _status(pending, reapproval)),
              ),
            ]),
            const SizedBox(height: 4),
            Row(children: [
              Expanded(child: Text(line, style: const TextStyle(fontSize: 12, color: AppColors.muted))),
              if (mine)
                IconButton(
                  tooltip: 'Edit',
                  visualDensity: VisualDensity.compact,
                  onPressed: () => _edit(b),
                  icon: const Icon(Icons.edit_rounded, size: 19, color: AppColors.primary),
                )
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

  Widget _status(bool pending, bool reapproval) {
    final colour = pending ? AppColors.warning : AppColors.success;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: colour.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(14)),
      child: Text(reapproval ? 'Pending re-approval' : (pending ? 'Pending approval' : 'Approved'),
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

  static const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  static const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

  String _nice(String iso) {
    final d = DateTime.tryParse(iso);
    if (d == null) return iso;
    return '${_weekdays[d.weekday - 1]}, ${d.day} ${_months[d.month - 1]} ${d.year}';
  }

  Widget _tabs() {
    Widget half(String text, int index) {
      final on = _tab == index;
      return Expanded(
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () {
            setState(() => _tab = index);
            if (index == 1 && _plans == null && !_plansLoading) _loadPlans();
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
      child: Row(children: [half('Outlets', 0), half('Plan dates', 1)]),
    );
  }

  /// The completed, upcoming and missed days of this beat, and the days still waiting for approval.
  List<Widget> _planRows() {
    final data = _plans;
    if (data == null) return const [];
    final today = DateTime.now();
    final todayIso = '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';
    final days = ((data['days'] as List?) ?? []).cast<Map<String, dynamic>>();
    final requested = ((data['requested'] as List?) ?? []).map((e) => '$e').toList();
    final done = [for (final d in days) if (d['status'] == 'done') d];
    final upcoming = [for (final d in days) if (d['status'] != 'done' && '${d['date']}'.compareTo(todayIso) >= 0) d]
      ..sort((a, b) => '${a['date']}'.compareTo('${b['date']}'));
    final missed = [for (final d in days) if (d['status'] != 'done' && '${d['date']}'.compareTo(todayIso) < 0) d];

    Widget group(String title, Color colour, List<Widget> rows) => rows.isEmpty
        ? const SizedBox.shrink()
        : Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Padding(
                padding: const EdgeInsets.only(left: 4, bottom: 6),
                child: Text('$title (${rows.length})', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 14, color: colour)),
              ),
              ...rows,
            ]),
          );

    Widget row(Map<String, dynamic> d, String note, Color colour, IconData icon) => Card(
          margin: const EdgeInsets.only(bottom: 8),
          child: ListTile(
            dense: true,
            leading: Icon(icon, color: colour),
            title: Text(_nice('${d['date']}'), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
            subtitle: Text(note, style: const TextStyle(fontSize: 12)),
          ),
        );

    String counts(Map<String, dynamic> d) =>
        '${d['completed_count'] ?? 0} of ${d['planned_count'] ?? 0} outlets visited';

    final rows = <Widget>[
      group('Completed', AppColors.success, [for (final d in done) row(d, counts(d), AppColors.success, Icons.check_circle_rounded)]),
      group('Planned', AppColors.primary, [
        for (final d in upcoming)
          row(d, d['status'] == 'in_progress' ? 'In progress · ${counts(d)}' : '${d['planned_count'] ?? 0} outlets planned',
              AppColors.primary, Icons.event_rounded),
      ]),
      group('Waiting for approval', AppColors.warning, [
        for (final iso in requested)
          row({'date': iso}, 'Will be planned once approved', AppColors.warning, Icons.hourglass_top_rounded),
      ]),
      group('Missed', AppColors.danger, [for (final d in missed) row(d, counts(d), AppColors.danger, Icons.event_busy_rounded)]),
    ];
    if (days.isEmpty && requested.isEmpty) {
      return const [EmptyView(icon: Icons.event_rounded, text: 'This beat has not been planned on any day yet.')];
    }
    return rows;
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await Services.api.get('/api/v1/route-plan/customers',
          query: {'beat_id': widget.beat['id'], 'date': fmtDate(DateTime.now()), 'member': 'me'}) as Map<String, dynamic>;
      if (mounted) setState(() => _outlets = ((data['customers'] as List?) ?? []).cast<Map<String, dynamic>>());
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _edit() async {
    final saved = await Navigator.of(context)
        .push<bool>(MaterialPageRoute(builder: (_) => EditBeatScreen(beat: widget.beat, outlets: _outlets)));
    if (saved == true) {
      _changed = true;
      await _load();
    }
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
            if (beatIsMine(b))
              IconButton(tooltip: 'Edit', onPressed: _edit, icon: const Icon(Icons.edit_rounded, color: AppColors.primary)),
          ],
        ),
        body: RefreshIndicator(
          onRefresh: () async {
            await _load();
            if (_tab == 1) await _loadPlans();
          },
          child: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 32), children: [
            _tabs(),
            if (_tab == 1) ...[
              if (_plansLoading) const LinearProgressIndicator(minHeight: 2),
              if (_plansError != null) ErrorView(message: _plansError!, onRetry: _loadPlans),
              ..._planRows(),
            ],
            if (_tab == 0) ...[
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

/// Edit Beat: the territory, and more outlets added to it. After saving, the beat goes to the manager
/// for approval again.
class EditBeatScreen extends StatefulWidget {
  const EditBeatScreen({super.key, required this.beat, this.outlets});

  final Map<String, dynamic> beat;

  /// The beat's outlets when already loaded; fetched here otherwise.
  final List<Map<String, dynamic>>? outlets;

  @override
  State<EditBeatScreen> createState() => _EditBeatScreenState();
}

class _EditBeatScreenState extends State<EditBeatScreen> {
  Set<int> _onBeat = {};
  final Set<int> _added = {};
  List<Map<String, dynamic>> _candidates = [];
  bool _loading = true;
  bool _busy = false;

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
      final found = await Services.api.get('/api/v1/clients', query: {'limit': 500});
      final list = found is Map ? (found['clients'] as List? ?? []) : (found as List? ?? []);
      if (!mounted) return;
      setState(() {
        _onBeat = {for (final o in outlets!) o['id'] as int};
        _candidates = [
          ...outlets,
          for (final c in list.cast<Map<String, dynamic>>())
            if (!outlets.any((o) => o['id'] == c['id']) && '${c['category_type'] ?? ''}'.toLowerCase() != 'lead') c,
        ];
      });
    } catch (e) {
      if (mounted) showProblem(context, e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  int get _selected => _onBeat.length + _added.length;

  Future<void> _pickOutlets() async {
    final picked = Set<int>.from(_added);
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheet) {
        var query = '';
        return StatefulBuilder(builder: (context, setSheet) {
          final q = query.trim().toLowerCase();
          final rows = [
            for (final c in _candidates)
              if (q.isEmpty || '${c['name']} ${c['city'] ?? ''}'.toLowerCase().contains(q)) c,
          ];
          return SafeArea(
            child: SizedBox(
              height: MediaQuery.of(context).size.height * 0.75,
              child: Column(children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: TextField(
                    onChanged: (v) => setSheet(() => query = v),
                    decoration: const InputDecoration(
                        prefixIcon: Icon(Icons.search_rounded), hintText: 'Search outlet…', isDense: true),
                  ),
                ),
                Expanded(
                  child: ListView.builder(
                    itemCount: rows.length,
                    itemBuilder: (_, i) {
                      final c = rows[i];
                      final id = c['id'] as int;
                      final already = _onBeat.contains(id);
                      // Outlets already on the beat stay: they are removed by the office, not from here.
                      return CheckboxListTile(
                        value: already || picked.contains(id),
                        onChanged: already ? null : (v) => setSheet(() => v == true ? picked.add(id) : picked.remove(id)),
                        controlAffinity: ListTileControlAffinity.leading,
                        title: Text('${c['name']}', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                        subtitle: Text(already ? 'On this beat' : '${c['city'] ?? c['address'] ?? ''}',
                            style: const TextStyle(fontSize: 12)),
                      );
                    },
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                  child: SizedBox(
                    width: double.infinity,
                    child: FilledButton(onPressed: () => Navigator.pop(sheet), child: const Text('Done')),
                  ),
                ),
              ]),
            ),
          );
        });
      },
    );
    if (mounted) {
      setState(() => _added
        ..clear()
        ..addAll(picked));
    }
  }

  Future<void> _save() async {
    if (_added.isEmpty) {
      showProblem(context, 'Add at least one outlet to save.');
      return;
    }
    setState(() => _busy = true);
    try {
      await Services.api.post('/api/v1/beats/${widget.beat['id']}/customers', {'partner_ids': _added.toList()});
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
            onPressed: _loading || _busy || _added.isEmpty ? null : _save,
          ),
        ),
      ),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 24), children: [
        _label('District / Territory'),
        _field(territory, locked: true),
        const SizedBox(height: 16),
        _label('Outlets'),
        _field(
          _loading
              ? 'Loading outlets…'
              : '$_selected outlet${_selected == 1 ? '' : 's'} selected${_added.isEmpty ? '' : ' (${_added.length} added)'}',
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
