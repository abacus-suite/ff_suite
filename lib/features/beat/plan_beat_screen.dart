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
  final Map<int, Set<int>> _selected = {};
  final Set<int> _loadingRoutes = {};
  bool _loading = true;
  bool _busy = false;
  String? _error;

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
        _selected[id] = customers.where((c) => c['selected'] == true).map((c) => c['id'] as int).toSet();
      });
    } catch (e) {
      if (mounted) showSnack(context, e.toString());
    } finally {
      if (mounted) setState(() => _loadingRoutes.remove(id));
    }
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
    for (final route in List.of(_chosen)) {
      await _loadCustomers(route);
    }
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

  @override
  Widget build(BuildContext context) {
    final routeLabel = Services.auth.profile!.routeLabel;
    final total = _selected.values.fold<int>(0, (s, v) => s + v.length);
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
                          onPressed: _busy || _chosen.isEmpty ? null : _save,
                        ),
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
                              leading: const CircleAvatar(
                                backgroundColor: Color(0xFFE8EFFF),
                                child: Icon(Icons.route_rounded, color: AppColors.primary),
                              ),
                              title: Text('${(d['beat'] as Map?)?['name'] ?? ''}',
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
