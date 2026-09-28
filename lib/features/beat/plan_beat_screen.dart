import 'dart:async';

import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../../core/format.dart';
import '../../core/services.dart';
import '../../core/theme.dart';
import '../../widgets/common.dart';

/// Create a beat plan: for me or someone in my team, one day, one or several routes,
/// with the customers of each route ticked. Saving opens the planned days.
class PlanBeatScreen extends StatefulWidget {
  const PlanBeatScreen({super.key});

  @override
  State<PlanBeatScreen> createState() => _PlanBeatScreenState();
}

class _PlanBeatScreenState extends State<PlanBeatScreen> {
  DateTime _date = DateUtils.dateOnly(DateTime.now());
  List<Map<String, dynamic>> _members = [];
  Map<String, dynamic>? _member; // null = me
  List<Map<String, dynamic>> _routes = [];
  final List<Map<String, dynamic>> _chosen = [];
  final Map<int, List<Map<String, dynamic>>> _customers = {};

  /// Who else has this beat, or one of its customers, planned for the same day.
  final Map<int, Map<String, dynamic>> _alsoPlanned = {};
  final Map<int, Set<int>> _selected = {};
  final Set<int> _loadingRoutes = {};
  bool _loading = true;
  bool _busy = false;
  String? _error;

  /// 'beat' picks a route and works through its customers; 'customer' picks the
  /// customers themselves. A lead has no beat, so it can only be planned the
  /// second way - and sometimes a day is simply a handful of shops.
  String _mode = 'beat';

  /// Contacts grouped by their beat, the beat-less ones last.
  List<Map<String, dynamic>> _groups = [];
  final Set<int> _picked = {};
  final Set<int> _visited = {};
  bool _loadingContacts = false;
  String _search = '';
  Timer? _searchDebounce;

  String get _memberParam => _member == null ? 'me' : '${_member!['id']}';

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    try {
      final team = await Services.api.get('/api/v1/team/members') as Map<String, dynamic>;
      _members = ((team['members'] as List?) ?? []).cast<Map<String, dynamic>>();
    } catch (_) {
      _members = [];
    }
    await _loadRoutes();
  }

  Future<void> _loadRoutes() async {
    setState(() {
      _loading = true;
      _error = null;
      _chosen.clear();
      _customers.clear();
      _selected.clear();
    });
    try {
      final list = (await Services.api.get('/api/v1/route-plan/routes', query: {'member': _memberParam}) as List)
          .cast<Map<String, dynamic>>();
      if (mounted) setState(() => _routes = list);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadCustomers(Map<String, dynamic> route) async {
    final id = route['id'] as int;
    setState(() => _loadingRoutes.add(id));
    try {
      final data = await Services.api.get('/api/v1/route-plan/customers',
          query: {'beat_id': id, 'date': fmtDate(_date), 'member': _memberParam}) as Map<String, dynamic>;
      final customers = ((data['customers'] as List?) ?? []).cast<Map<String, dynamic>>();
      if (!mounted) return;
      setState(() {
        _customers[id] = customers;
        _alsoPlanned[id] = (data['already_planned'] as Map?)?.cast<String, dynamic>() ?? const {};
        _selected[id] = customers.where((c) => c['selected'] == true).map((c) => c['id'] as int).toSet();
      });
    } catch (e) {
      if (mounted) showSnack(context, e.toString());
    } finally {
      if (mounted) setState(() => _loadingRoutes.remove(id));
    }
  }

  /// Everything this person may plan, grouped by beat, with today's ticks kept.
  Future<void> _loadContacts() async {
    setState(() => _loadingContacts = true);
    try {
      final data = await Services.api.get('/api/v1/route-plan/contacts', query: {
        'date': fmtDate(_date),
        'member': _memberParam,
        if (_search.trim().isNotEmpty) 'q': _search.trim(),
      }) as Map<String, dynamic>;
      final groups = ((data['groups'] as List?) ?? []).cast<Map<String, dynamic>>();
      if (!mounted) return;
      setState(() {
        _groups = groups;
        // Ticks already saved for that day come back ticked; a search must not lose them.
        for (final group in groups) {
          for (final c in ((group['customers'] as List?) ?? []).cast<Map<String, dynamic>>()) {
            final id = c['id'] as int;
            if (c['selected'] == true) _picked.add(id);
            if (c['visited'] == true) _visited.add(id);
          }
        }
      });
    } catch (e) {
      if (mounted) showSnack(context, e.toString());
    } finally {
      if (mounted) setState(() => _loadingContacts = false);
    }
  }

  void _onSearch(String value) {
    _search = value;
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 350), _loadContacts);
  }

  Future<void> _pickMember() async {
    final picked = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheet) => SizedBox(
        height: MediaQuery.of(sheet).size.height * 0.7,
        child: ListView(
          children: [
            ListTile(
              leading: const Icon(Icons.person_rounded, color: AppColors.primary),
              title: const Text('Myself', style: TextStyle(fontWeight: FontWeight.w700)),
              trailing: _member == null ? const Icon(Icons.check_rounded, color: AppColors.primary) : null,
              onTap: () => Navigator.pop(sheet, <String, dynamic>{}),
            ),
            const Divider(),
            for (final m in _members)
              ListTile(
                leading: const Icon(Icons.person_outline_rounded),
                title: Text('${m['name']}'),
                subtitle: Text([if (m['code'] != null) m['code'], if (m['team'] is Map) (m['team'] as Map)['name']]
                    .join(' · ')),
                trailing: _member?['id'] == m['id'] ? const Icon(Icons.check_rounded, color: AppColors.primary) : null,
                onTap: () => Navigator.pop(sheet, m),
              ),
          ],
        ),
      ),
    );
    if (picked == null) return;
    setState(() => _member = picked.isEmpty ? null : picked);
    await _loadRoutes();
  }

  Future<void> _pickDate() async {
    final now = DateUtils.dateOnly(DateTime.now());
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: now,
      lastDate: now.add(const Duration(days: 120)),
    );
    if (picked == null) return;
    setState(() => _date = picked);
    if (_mode == 'customer') {
      _picked.clear();
      _visited.clear();
      await _loadContacts();
      return;
    }
    for (final route in List.of(_chosen)) {
      await _loadCustomers(route);
    }
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    super.dispose();
  }

  Future<void> _pickRoutes(String routeLabel) async {
    final chosenIds = _chosen.map((r) => r['id'] as int).toSet();
    final result = await showModalBottomSheet<Set<int>>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheet) {
        var query = '';
        final picked = {...chosenIds};
        return StatefulBuilder(builder: (context, setSheet) {
          final q = query.trim().toLowerCase();
          final shown = q.isEmpty
              ? _routes
              : _routes.where((r) => '${r['name']} ${r['city'] ?? ''}'.toLowerCase().contains(q)).toList();
          return SizedBox(
            height: MediaQuery.of(context).size.height * 0.8,
            child: Padding(
              padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                    child: TextField(
                      onChanged: (v) => setSheet(() => query = v),
                      decoration: InputDecoration(
                          prefixIcon: const Icon(Icons.search_rounded), hintText: 'Search $routeLabel', isDense: true),
                    ),
                  ),
                  Expanded(
                    child: ListView.builder(
                      itemCount: shown.length,
                      itemBuilder: (context, i) {
                        final r = shown[i];
                        final id = r['id'] as int;
                        return CheckboxListTile(
                          value: picked.contains(id),
                          onChanged: (on) => setSheet(() => on == true ? picked.add(id) : picked.remove(id)),
                          title: Text('${r['name']}', style: const TextStyle(fontWeight: FontWeight.w600)),
                          subtitle: Text([
                            if (r['city'] != null) r['city'],
                            '${r['customer_count']} customers',
                            if ((r['planned_km'] as num? ?? 0) > 0) '${r['planned_km']} km',
                          ].join(' · ')),
                        );
                      },
                    ),
                  ),
                  SafeArea(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: SizedBox(
                        width: double.infinity,
                        child: FilledButton(
                          onPressed: () => Navigator.pop(sheet, picked),
                          child: Text('Use ${picked.length} ${picked.length == 1 ? routeLabel : '${routeLabel}s'}'),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        });
      },
    );
    if (result == null) return;
    final next = _routes.where((r) => result.contains(r['id'])).toList();
    setState(() {
      _chosen
        ..clear()
        ..addAll(next);
      _customers.removeWhere((id, _) => !result.contains(id));
      _selected.removeWhere((id, _) => !result.contains(id));
    });
    for (final route in next) {
      if (!_customers.containsKey(route['id'])) await _loadCustomers(route);
    }
  }

  Future<void> _save() async {
    if (_mode == 'customer') return _saveCustomers();
    final routes = [
      for (final r in _chosen)
        if ((_selected[r['id']] ?? {}).isNotEmpty) {'beat_id': r['id'], 'partner_ids': _selected[r['id']]!.toList()},
    ];
    if (routes.isEmpty) {
      showSnack(context, 'Choose at least one route with customers.');
      return;
    }
    setState(() => _busy = true);
    try {
      final result = await Services.outbox.submit('/api/v1/route-plan/days', {
        'uuid': const Uuid().v4(),
        'date': fmtDate(_date),
        'member': _memberParam,
        'routes': routes,
      });
      Services.refresh.value++;
      if (!mounted) return;
      if (result.queued) {
        showSnack(context, 'Saved on the phone; it will be planned when you are online.');
      }
      Navigator.of(context).pushReplacement(MaterialPageRoute(
        builder: (_) => PlannedDaysScreen(
          member: _memberParam,
          memberName: _member == null ? null : '${_member!['name']}',
          start: _date,
        ),
      ));
    } catch (e) {
      if (mounted) showSnack(context, e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// The day is the customers themselves: one plan, whatever beats they sit on.
  Future<void> _saveCustomers() async {
    if (_picked.isEmpty) {
      showSnack(context, 'Choose at least one customer.');
      return;
    }
    setState(() => _busy = true);
    try {
      final result = await Services.outbox.submit('/api/v1/route-plan/days', {
        'uuid': const Uuid().v4(),
        'date': fmtDate(_date),
        'member': _memberParam,
        'partner_ids': _picked.toList(),
      });
      Services.refresh.value++;
      if (!mounted) return;
      if (result.queued) {
        showSnack(context, 'Saved on the phone; it will be planned when you are online.');
      }
      Navigator.of(context).pushReplacement(MaterialPageRoute(
        builder: (_) => PlannedDaysScreen(
          member: _memberParam,
          memberName: _member == null ? null : '${_member!['name']}',
          start: _date,
        ),
      ));
    } catch (e) {
      if (mounted) showSnack(context, e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final routeLabel = Services.auth.profile!.routeLabel;
    final total = _mode == 'customer'
        ? _picked.length
        : _selected.values.fold<int>(0, (s, v) => s + v.length);
    return Scaffold(
      appBar: AppBar(title: const Text('Create Beat Plan')),
      body: _loading && _routes.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? ErrorView(message: _error!, onRetry: _loadRoutes)
              : Column(
                  children: [
                    Expanded(
                      child: ListView(
                        padding: const EdgeInsets.all(16),
                        children: [
                          if (_members.isNotEmpty)
                            Card(
                              child: ListTile(
                                leading: const Icon(Icons.people_alt_rounded, color: AppColors.primary),
                                title: const Text('Plan for'),
                                subtitle: Text(_member == null ? 'Myself' : '${_member!['name']}',
                                    style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.text)),
                                trailing: const Icon(Icons.chevron_right_rounded),
                                onTap: _pickMember,
                              ),
                            ),
                          Card(
                            child: ListTile(
                              leading: const Icon(Icons.calendar_month_rounded, color: AppColors.primary),
                              title: const Text('Day'),
                              trailing: Text(fmtDate(_date), style: const TextStyle(fontWeight: FontWeight.w700)),
                              onTap: _pickDate,
                            ),
                          ),
                          _modeToggle(routeLabel),
                          if (_mode == 'customer') ...[
                            const SizedBox(height: 6),
                            ..._contactPicker(),
                          ] else
                          Card(
                            child: ListTile(
                              leading: const Icon(Icons.route_rounded, color: AppColors.primary),
                              title: Text(_chosen.isEmpty
                                  ? 'Choose ${routeLabel}s'
                                  : '${_chosen.length} ${_chosen.length == 1 ? routeLabel : '${routeLabel}s'} chosen'),
                              subtitle: Text(_routes.isEmpty
                                  ? 'No $routeLabel assigned'
                                  : _chosen.isEmpty
                                      ? 'You can pick several at once'
                                      : _chosen.map((r) => r['name']).join(', '),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis),
                              trailing: const Icon(Icons.playlist_add_check_rounded),
                              onTap: _routes.isEmpty ? null : () => _pickRoutes(routeLabel),
                            ),
                          ),
                          const SizedBox(height: 6),
                          if (_mode == 'beat')
                            for (final route in _chosen) _routeSection(route),
                        ],
                      ),
                    ),
                    SafeArea(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: GradientButton(
                          label: total == 0 ? 'Save Plan' : 'Save Plan · $total customers',
                          icon: Icons.event_available_rounded,
                          busy: _busy,
                          onPressed: _busy || total == 0 ? null : _save,
                        ),
                      ),
                    ),
                  ],
                ),
    );
  }

  /// Which way the day is planned. Beat wise is the old flow untouched.
  Widget _modeToggle(String routeLabel) => Card(
        margin: const EdgeInsets.only(bottom: 4),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Plan by', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: SegmentedButton<String>(
                  segments: [
                    ButtonSegment(
                      value: 'beat',
                      label: Text('${routeLabel[0].toUpperCase()}${routeLabel.substring(1)} wise'),
                      icon: const Icon(Icons.route_rounded, size: 17),
                    ),
                    const ButtonSegment(
                      value: 'customer',
                      label: Text('Customer wise'),
                      icon: Icon(Icons.storefront_rounded, size: 17),
                    ),
                  ],
                  showSelectedIcon: false,
                  selected: {_mode},
                  onSelectionChanged: (choice) async {
                    setState(() => _mode = choice.first);
                    if (_mode == 'customer' && _groups.isEmpty) await _loadContacts();
                  },
                ),
              ),
              const SizedBox(height: 7),
              Text(
                _mode == 'customer'
                    ? 'Pick the customers themselves. They are grouped by $routeLabel, and a lead with no '
                        '$routeLabel yet sits in its own group.'
                    : 'Pick a $routeLabel and work through its customers.',
                style: const TextStyle(fontSize: 12, color: AppColors.muted),
              ),
            ],
          ),
        ),
      );

  /// The customer picker: a search box and one section per beat.
  List<Widget> _contactPicker() {
    return [
      Card(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  onChanged: _onSearch,
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search_rounded),
                    hintText: 'Search customers, leads, city',
                    isDense: true,
                    border: InputBorder.none,
                  ),
                ),
              ),
              if (_loadingContacts)
                const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
            ],
          ),
        ),
      ),
      if (_picked.isNotEmpty)
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 8, 4, 2),
          child: Row(
            children: [
              Expanded(
                child: Text('${_picked.length} chosen for ${fmtDate(_date)}',
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
              ),
              TextButton(onPressed: () => setState(_picked.clear), child: const Text('Clear')),
            ],
          ),
        ),
      if (!_loadingContacts && _groups.isEmpty)
        const Padding(
          padding: EdgeInsets.only(top: 24),
          child: EmptyView(icon: Icons.person_search_rounded, text: 'No contacts match'),
        ),
      for (final group in _groups) _contactGroup(group),
      const SizedBox(height: 8),
    ];
  }

  Widget _contactGroup(Map<String, dynamic> group) {
    final customers = ((group['customers'] as List?) ?? []).cast<Map<String, dynamic>>();
    final free = group['beat'] == null;
    final chosen = customers.where((c) => _picked.contains(c['id'])).length;
    return Card(
      child: ExpansionTile(
        initiallyExpanded: _groups.length <= 2 || chosen > 0,
        leading: Icon(free ? Icons.person_pin_circle_rounded : Icons.route_rounded,
            color: free ? AppColors.purple : AppColors.primary),
        title: Text('${group['name']}', style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text('$chosen of ${customers.length} chosen'),
        children: [
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: () => setState(() {
                final ids = customers
                    .where((c) => !_visited.contains(c['id']))
                    .map((c) => c['id'] as int)
                    .toList();
                if (chosen >= ids.length) {
                  _picked.removeAll(ids);
                } else {
                  _picked.addAll(ids);
                }
              }),
              child: Text(chosen >= customers.length ? 'Clear all' : 'Select all'),
            ),
          ),
          for (final c in customers)
            CheckboxListTile(
              dense: true,
              controlAffinity: ListTileControlAffinity.leading,
              value: _picked.contains(c['id']),
              onChanged: _visited.contains(c['id'])
                  ? null
                  : (on) => setState(() =>
                      on == true ? _picked.add(c['id'] as int) : _picked.remove(c['id'])),
              title: Text('${c['name']}'),
              subtitle: Text([
                if (_visited.contains(c['id'])) 'Visited on this day' else lastVisitLabel(c),
                if (c['city'] != null) '${c['city']}',
                // Two people may call on the same shop; this only says so.
                if ((c['also_planned_by'] as List?)?.isNotEmpty == true)
                  'also planned by ${(c['also_planned_by'] as List).join(', ')}',
              ].join(' · ')),
            ),
        ],
      ),
    );
  }

  /// A quiet note when somebody else is going there too. Never a block: two
  /// people calling on the same shop on the same day is normal work.
  Widget _alsoPlannedNote(int routeId) {
    final planned = _alsoPlanned[routeId] ?? const {};
    final onBeat = ((planned['beat'] as List?) ?? []).cast<Map<String, dynamic>>();
    final onCustomers = ((planned['customers'] as List?) ?? []).cast<Map<String, dynamic>>();
    if (onBeat.isEmpty && onCustomers.isEmpty) return const SizedBox.shrink();
    final lines = <String>[
      if (onBeat.isNotEmpty)
        '${onBeat.map((e) => '${e['name']}').join(', ')} already planned this beat today.',
      for (final row in onCustomers.take(4))
        '${row['name']}: also planned by ${((row['people'] as List?) ?? []).join(', ')}.',
      if (onCustomers.length > 4) 'and ${onCustomers.length - 4} more customers.',
    ];
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 4, 12, 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.warning.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline_rounded, size: 17, color: AppColors.warning),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final line in lines)
                  Text(line, style: const TextStyle(fontSize: 12, color: AppColors.text)),
                const SizedBox(height: 2),
                const Text('You can still plan it; two people may visit the same day.',
                    style: TextStyle(fontSize: 11.5, color: AppColors.muted)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _routeSection(Map<String, dynamic> route) {
    final id = route['id'] as int;
    final customers = _customers[id] ?? [];
    final selected = _selected[id] ?? <int>{};
    return Card(
      child: ExpansionTile(
        initiallyExpanded: _chosen.length == 1,
        leading: const Icon(Icons.route_rounded, color: AppColors.primary),
        title: Text('${route['name']}', style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text(_loadingRoutes.contains(id) ? 'Loading customers…' : '${selected.length} of ${customers.length} customers'),
        children: [
          _alsoPlannedNote(id),
          if (customers.isNotEmpty)
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () => setState(() {
                  if (selected.length == customers.length) {
                    _selected[id] = customers.where((c) => c['visited'] == true).map((c) => c['id'] as int).toSet();
                  } else {
                    _selected[id] = customers.map((c) => c['id'] as int).toSet();
                  }
                }),
                child: Text(selected.length == customers.length ? 'Clear all' : 'Select all'),
              ),
            ),
          for (final c in customers)
            CheckboxListTile(
              dense: true,
              controlAffinity: ListTileControlAffinity.leading,
              value: selected.contains(c['id']),
              onChanged: c['visited'] == true
                  ? null
                  : (on) => setState(() {
                        final set = _selected.putIfAbsent(id, () => <int>{});
                        on == true ? set.add(c['id'] as int) : set.remove(c['id']);
                      }),
              title: Text('${c['name']}'),
              subtitle: Text(c['visited'] == true ? 'Visited on this day' : lastVisitLabel(c)),
            ),
        ],
      ),
    );
  }
}

/// Days already planned, for me or one team member, from [start] for two weeks.
class PlannedDaysScreen extends StatefulWidget {
  const PlannedDaysScreen({super.key, this.member = 'me', this.memberName, required this.start});

  final String member;
  final String? memberName;
  final DateTime start;

  @override
  State<PlannedDaysScreen> createState() => _PlannedDaysScreenState();
}

class _PlannedDaysScreenState extends State<PlannedDaysScreen> {
  List<Map<String, dynamic>> _days = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final list = (await Services.api.get('/api/v1/route-plan/days', query: {
        'member': widget.member,
        'start': fmtDate(widget.start),
        'end': fmtDate(widget.start.add(const Duration(days: 13))),
      }) as List)
          .cast<Map<String, dynamic>>();
      if (mounted) setState(() => _days = list);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final byDate = <String, List<Map<String, dynamic>>>{};
    for (final d in _days) {
      byDate.putIfAbsent('${d['date']}', () => []).add(d);
    }
    final dates = byDate.keys.toList()..sort();
    return Scaffold(
      appBar: AppBar(title: Text(widget.memberName == null ? 'Planned Days' : 'Plan · ${widget.memberName}')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.of(context)
            .push(MaterialPageRoute(builder: (_) => const PlanBeatScreen()))
            .then((_) => _load()),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Plan more'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? ErrorView(message: _error!, onRetry: _load)
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                    children: [
                      if (dates.isEmpty)
                        const EmptyView(icon: Icons.event_busy_rounded, text: 'Nothing planned in the next two weeks'),
                      for (final date in dates) ...[
                        Padding(
                          padding: const EdgeInsets.fromLTRB(4, 12, 4, 6),
                          child: Text(date, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                        ),
                        for (final d in byDate[date]!)
                          Card(
                            child: ListTile(
                              leading: CircleAvatar(
                                backgroundColor: const Color(0xFFE8EFFF),
                                child: Icon(
                                    d['beat'] == null
                                        ? Icons.person_pin_circle_rounded
                                        : Icons.route_rounded,
                                    color: d['beat'] == null ? AppColors.purple : AppColors.primary),
                              ),
                              // A day picked customer by customer has no route to name.
                              title: Text('${(d['beat'] as Map?)?['name'] ?? 'Chosen customers'}',
                                  style: const TextStyle(fontWeight: FontWeight.w700)),
                              subtitle: Text([
                                if (d['employee'] is Map && widget.member == 'team') (d['employee'] as Map)['name'],
                                '${d['planned_count']} planned',
                                '${d['completed_count']} visited',
                                if ((d['missed_count'] as num? ?? 0) > 0) '${d['missed_count']} missed',
                              ].join(' · ')),
                              trailing: StatusBadge('${d['status'] ?? 'planned'}'),
                            ),
                          ),
                      ],
                    ],
                  ),
                ),
    );
  }
}
