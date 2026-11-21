import 'dart:async';
import '../../core/pdf_download.dart';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../../core/format.dart';
import '../../core/geo.dart';
import '../../core/services.dart';
import '../../core/theme.dart';
import '../../widgets/common.dart';
import 'add_visit_screen.dart';
import 'added_visits.dart';
import '../clients/client_detail_screen.dart';
import '../clients/clients_screen.dart';
import '../tasks/task_docs_screen.dart';
import '../tasks/tasks_screen.dart';

const _weekdayNames = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];

/// The day's journey plan: one or several routes, each customer with its plan status.
class BeatTodayScreen extends StatefulWidget {
  const BeatTodayScreen({super.key, this.embedded = false, this.filter = 'all'});

  final bool embedded;

  /// Which of today's customers to list: all, visited, pending or cancelled.
  final String filter;

  @override
  State<BeatTodayScreen> createState() => _BeatTodayScreenState();
}

class _BeatTodayScreenState extends State<BeatTodayScreen> {
  // Only today's plan is shown: no other day can be opened from here.
  final DateTime _day = DateTime.now();
  late String _filter = widget.filter;

  /// The beat the list below is narrowed to (its id, or 'none' for the plan with no beat); null shows every beat.
  String? _beat;
  Map<String, dynamic>? _data;
  bool _loading = true;
  String? _error;

  /// 0: planned customers, 1: unplanned tasks (offsite/onsite + manager tasks), 2: completed tasks.
  int _tab = 0;
  List<Map<String, dynamic>> _tasks = [];

  /// Open manager-assigned tasks from the backend (ff.task, state todo/in_progress, assigned_by set).
  List<Map<String, dynamic>> _managerTasks = [];

  /// Where the phone is: today's outlets are listed nearest first from here.
  Position? _here;
  Timer? _follow;

  /// Outlets added to today with "Add a Visit" and not visited yet.
  List<Map<String, dynamic>> _added = [];

  bool get _isToday => fmtDate(_day) == fmtDate(DateTime.now());

  @override
  void initState() {
    super.initState();
    Services.refresh.addListener(_load);
    _load();
    // As the person moves the order follows them: the nearest outlet stays on top.
    _follow = Timer.periodic(const Duration(seconds: 60), (_) => _moved());
  }

  @override
  void dispose() {
    _follow?.cancel();
    Services.refresh.removeListener(_load);
    super.dispose();
  }

  /// A newer fix, without asking for one, reorders the list once the person has moved a little.
  Future<void> _moved() async {
    final last = await lastKnownPosition();
    final here = _here;
    if (!mounted || last == null || last.isMocked) return;
    if (here == null || Geolocator.distanceBetween(here.latitude, here.longitude, last.latitude, last.longitude) > 50) {
      setState(() => _here = last);
    }
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() => _loading = true);
    try {
      final pos = await lastKnownPosition();
      if (pos != null && !pos.isMocked) _here = pos;
      _added = await AddedVisits.today();
      final results = await Future.wait<dynamic>([
        Services.api.get('/api/v1/beat/today', query: {
          'date': fmtDate(_day),
          if (pos != null) 'lat': pos.latitude,
          if (pos != null) 'lng': pos.longitude,
        }),
        Services.api.get('/api/v1/tasks', query: {
          'scope': 'mine',
          'state': 'todo,in_progress,done',
        }).catchError((_) => <String, dynamic>{}),
      ]);

      final data = results[0] as Map<String, dynamic>;
      final taskData = results[1] is Map ? results[1] as Map<String, dynamic> : <String, dynamic>{};

      // The same list the Planned card counts, so the tab, the card and the report agree.
      _tasks = ((data['tasks'] as List?) ?? const []).cast<Map<String, dynamic>>();

      final dayStr = fmtDate(_day);
      final mgrFromBeat = ((data['tasks_manager'] as List?) ?? const []).cast<Map<String, dynamic>>();
      final mgrFromTasks = ((taskData['tasks'] as List?) ?? const []).cast<Map<String, dynamic>>();

      final byId = <dynamic, Map<String, dynamic>>{};
      for (final t in mgrFromBeat) {
        final due = asText(t['due']);
        if (due != null && due.startsWith(dayStr)) {
          byId[t['id']] = t;
        }
      }
      for (final t in mgrFromTasks) {
        final due = asText(t['due']);
        if (due != null && due.startsWith(dayStr)) {
          byId[t['id']] = t;
        }
      }
      _managerTasks = byId.values.toList();
      if (mounted) setState(() => (_data = data, _error = null));
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Cancel a planned visit of today, with the reason; a cancelled one can be planned again.
  Future<void> _cancelVisit(Map<String, dynamic> client, {bool undo = false}) async {
    String? reason;
    if (!undo) {
      final text = TextEditingController();
      reason = await showDialog<String>(
        context: context,
        builder: (dialog) => StatefulBuilder(
          builder: (context, set) => AlertDialog(
            title: const Text('Cancel this visit'),
            content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${client['name']}', style: const TextStyle(fontWeight: FontWeight.w800)),
              const SizedBox(height: 10),
              TextField(
                controller: text,
                autofocus: true,
                minLines: 2,
                maxLines: 4,
                onChanged: (_) => set(() {}),
                decoration: const InputDecoration(labelText: 'Reason *', border: OutlineInputBorder()),
              ),
            ]),
            actions: [
              TextButton(onPressed: () => Navigator.pop(dialog), child: const Text('Back')),
              FilledButton(
                onPressed: text.text.trim().isEmpty ? null : () => Navigator.pop(dialog, text.text.trim()),
                child: const Text('Cancel visit'),
              ),
            ],
          ),
        ),
      );
      text.dispose();
      if (reason == null) return;
    }
    try {
      await Services.api.post('/api/v1/route-plan/customers/cancel', {
        'partner_id': client['id'],
        'date': fmtDate(_day),
        if (undo) 'undo': true else 'reason': reason,
      });
      if (!mounted) return;
      showSnack(context, undo ? 'Planned again' : 'Visit cancelled');
      await _load();
    } catch (e) {
      if (mounted) showProblem(context, e.toString());
    }
  }

  Future<void> _openClient(int id) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => ClientDetailScreen(clientId: id)));
    _load();
  }

  /// Add a Visit: tick outlets not in today's beat; they join today's list by distance.
  /// On another day it stays as it was: pick anyone and their page opens.
  Future<void> _adhoc() async {
    if (!_isToday) {
      final client = await Navigator.of(context).push<Map<String, dynamic>>(
          MaterialPageRoute(builder: (_) => const ClientsScreen(pickMode: true, title: 'Add a Visit')));
      if (client != null) await _openClient(client['id'] as int);
      return;
    }
    final data = _data;
    final skip = <Object?>{
      for (final c in ((data?['clients'] as List?) ?? []).cast<Map>()) c['id'],
      for (final a in _added) a['id'],
    };
    final added = await Navigator.of(context)
        .push<bool>(MaterialPageRoute(builder: (_) => AddVisitScreen(skipIds: skip)));
    if (added == true) await _load();
  }

  @override
  Widget build(BuildContext context) {
    final label = Services.auth.profile!.routeLabel;
    return Scaffold(
      appBar: AppBar(
        actions: [
          IconButton(
            icon: const Icon(Icons.download_rounded),
            tooltip: 'Download Beat Plan report',
            onPressed: () {
              downloadAndSaveExcel(
                context,
                endpoint: '/api/v1/beat/today/excel?date=${fmtDate(_day)}',
                filename: 'Today_Beat_Plan_${fmtDate(_day)}.xlsx',
              );
            },
          ),
        ],
        automaticallyImplyLeading: !widget.embedded,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(fmtDate(_day) == fmtDate(DateTime.now()) ? "Today's Beat Plan" : 'Beat Plan',
                style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
            Text('${_weekdayNames[_day.weekday - 1].substring(0, 3)}, ${_day.day.toString().padLeft(2, '0')} ${monthNames[_day.month - 1].substring(0, 3)} ${_day.year}'
                '${_isToday ? ' · nearest first' : ''}',
                style: const TextStyle(fontSize: 11.5, color: AppColors.muted, fontWeight: FontWeight.w500)),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _adhoc,
        icon: const Icon(Icons.add_rounded),
        label: const Text('Add a Visit'),
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
          children: [
            if (_loading) const LinearProgressIndicator(),
            if (_error != null && _data == null) ErrorView(message: _error!, onRetry: _load),
            if (_data != null) ..._content(_data!, label),
          ],
        ),
      ),
    );
  }

  List<Widget> _content(Map<String, dynamic> data, String label) {
    final plans = ((data['plans'] as List?) ?? []).cast<Map<String, dynamic>>();
    final every = ((data['clients'] as List?) ?? []).cast<Map<String, dynamic>>();
    final clients = every.where((c) {
      if (_beat != null && !_inBeat(c, plans)) return false;
      if (_filter == 'all') return true;
      final status = c['visit_status'] == 'done' ? 'visited' : (c['plan_status'] as String? ?? 'planned');
      return switch (_filter) {
        'visited' => status == 'visited',
        'cancelled' => status == 'cancelled',
        'offsite' => false, // offsite visits are added visits, below
        _ => status != 'visited' && status != 'cancelled' && status != 'skipped',
      };
    }).toList();
    final adhoc = ((data['adhoc_visits'] as List?) ?? []).cast<Map<String, dynamic>>();
    if (_isToday) return _todayContent(plans, clients, adhoc, label);
    return [
      _statBoxes(plans),
      _filters(plans),
      if (plans.isEmpty)
        EmptyView(icon: Icons.event_busy_rounded,
            text: 'No $label planned for this day.\nUse "Add a Visit" to visit anyone.'),
      if (clients.isEmpty && _filter != 'all')
        const EmptyView(icon: Icons.filter_alt_off_rounded, text: 'Nothing in this group.'),
      if (clients.isNotEmpty) ...[
        const Padding(
          padding: EdgeInsets.fromLTRB(4, 14, 4, 4),
          child: Text('Customers', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
        ),
        for (final client in clients) _clientTile(client, showRoute: plans.length > 1),
      ],
      if (adhoc.isNotEmpty && _filter == 'all') ...[
        const Padding(
          padding: EdgeInsets.fromLTRB(4, 14, 4, 4),
          child: Text('Add a Visit', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
        ),
        for (final visit in adhoc)
          Card(
            child: ListTile(
              leading: const CircleAvatar(backgroundColor: Color(0xFFEDE8FF), child: Icon(Icons.bolt_rounded, color: AppColors.purple)),
              title: Text('${(visit['client'] as Map)['name']}'),
              subtitle: Text('${fmtTime(visit['check_in_at'])}–${fmtTime(visit['check_out_at'])}'),
              trailing: StatusBadge(visit['state'] == 'ongoing' ? 'ongoing' : 'visited'),
              onTap: () => _openClient((visit['client'] as Map)['id'] as int),
            ),
          ),
      ],
    ];
  }

  /// Today: the planned outlets and the visits added to the day in one list, nearest first, so the
  /// nearest outlet is always on top. Other days keep the planned order.
  List<Widget> _todayContent(List<Map<String, dynamic>> plans, List<Map<String, dynamic>> clients,
      List<Map<String, dynamic>> adhoc, String label) {
    // Only visits for contacts that were explicitly added to today's beat via "Add a Visit"
    final addedIds = {for (final a in _added) a['id']};
    final every = [
      for (final visit in adhoc)
        if (addedIds.contains((visit['client'] as Map?)?['id']))
          if (_filter == 'all' ||
              (_filter == 'visited' && visit['state'] != 'ongoing' && '${visit['visit_type']}' != 'offsite') ||
              (_filter == 'offsite' && visit['state'] != 'ongoing' && '${visit['visit_type']}' == 'offsite') ||
              ((_filter == 'pending' || _filter == 'planned') && visit['state'] == 'ongoing'))
            {...(visit['client'] as Map).cast<String, dynamic>(), '_visit': visit},
    ];
    // A customer visited more than once today is one row (the timeline has each visit): the one still running,
    // otherwise the latest, with how many visits there were.
    final byClient = <Object?, Map<String, dynamic>>{};
    final counts = <Object?, int>{};
    for (final row in every) {
      final id = row['id'];
      counts[id] = (counts[id] ?? 0) + 1;
      final kept = byClient[id];
      final visit = row['_visit'] as Map;
      final keptVisit = kept?['_visit'] as Map?;
      final better = kept == null ||
          (visit['state'] == 'ongoing' && keptVisit?['state'] != 'ongoing') ||
          (keptVisit?['state'] != 'ongoing' && '${visit['check_in_at']}'.compareTo('${keptVisit?['check_in_at']}') > 0);
      if (better) byClient[id] = row;
    }
    final added = [
      for (final e in byClient.entries) {...e.value, '_visits': counts[e.key] ?? 1},
    ];
    // Added with "Add a Visit" and not visited yet: pending, until the server has the visit.
    final visited = {for (final v in adhoc) if (addedIds.contains((v['client'] as Map?)?['id'])) (v['client'] as Map?)?['id']};
    final planned = {for (final c in ((_data?['clients'] as List?) ?? []).cast<Map>()) c['id']};
    final waiting = [
      if (_filter == 'all' || _filter == 'pending' || _filter == 'planned')
        for (final a in _added)
          if (!visited.contains(a['id']) && !planned.contains(a['id'])) {...a, '_visit': const {'state': 'added'}},
    ];
    // Visits added by hand belong to no beat: they are left out while one beat is chosen.
    final rows = nearestFirst([...clients, if (_beat == null) ...added, if (_beat == null) ...waiting], _here);
    return [
      _tabSwitch(),
      if (_tab == 2) ..._completedTasks()
      else if (_tab == 1) ..._unplannedTab()
      else ...[ // tab 0 — planned customers
      _filters(plans),
      if (plans.isEmpty && rows.isEmpty && _filter == 'all')
        EmptyView(icon: Icons.event_busy_rounded,
            text: 'No $label planned for this day.\nUse "Add a Visit" to visit anyone.'),
      if (rows.isEmpty && _filter != 'all')
        const EmptyView(icon: Icons.filter_alt_off_rounded, text: 'Nothing in this group.'),
      if (rows.isNotEmpty) ...[
        const Padding(
          padding: EdgeInsets.fromLTRB(4, 14, 4, 4),
          child: Text('Customers', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
        ),
        for (final (i, row) in rows.indexed)
          row['_visit'] is Map
              ? _addedTile(row, i + 1)
              : _clientTile(row, showRoute: plans.length > 1, number: i + 1),
        Container(
          margin: const EdgeInsets.only(top: 6),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: AppColors.warning.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.warning.withValues(alpha: 0.3)),
          ),
          child: const Text('Order changes as you move – the nearest outlet is always on top.',
              style: TextStyle(fontSize: 12, color: Color(0xFF9A3412))),
        ),
      ],
      ],
    ];
  }

  Widget _tabSwitch() {
    final allClients = ((_data?['clients'] as List?) ?? const []).cast<Map>();
    final plannedTotal = allClients.length + _added.length;
    final unplannedTasks = _tasks.where((t) => !_isTaskPlanned(t)).toList();
    final unplannedTotal = unplannedTasks.length + _managerTasks.length;
    final doneManagerCount = _managerTasks.where((t) => t['state'] == 'done').length;
    final completedTotal = _tasks.length + doneManagerCount;
    final tabs = [
      (0, 'Planned', plannedTotal),
      (1, 'Unplanned', unplannedTotal),
      (2, 'Completed', completedTotal),
    ];
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
          color: Colors.white, borderRadius: BorderRadius.circular(23), border: Border.all(color: AppColors.border)),
      child: Row(children: [
        for (final (i, text, count) in tabs)
          Expanded(
            child: InkWell(
              borderRadius: BorderRadius.circular(20),
              onTap: () => setState(() => _tab = i),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 10),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: _tab == i ? AppColors.primary.withValues(alpha: 0.12) : Colors.transparent,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  count != null ? '$text ($count)' : text,
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                    color: _tab == i ? AppColors.primary : AppColors.text,
                  ),
                ),
              ),
            ),
          ),
      ]),
    );
  }

  Set<int> get _plannedPartnerIds => {
        for (final c in ((_data?['clients'] as List?) ?? const []).cast<Map>())
          if (c['id'] is int) c['id'] as int,
      };

  bool _isTaskPlanned(Map<String, dynamic> t) {
    if (t['is_planned'] != null) return t['is_planned'] == true;
    final id = t['partner_id'];
    return id is int && _plannedPartnerIds.contains(id);
  }

  /// Tab 1: Unplanned tab showing default two groups: By manager and By self.
  List<Widget> _unplannedTab() {
    final unplannedTasks = _tasks.where((t) => !_isTaskPlanned(t)).toList();
    return [
      _simpleGroupCard(
        title: 'By manager',
        count: _managerTasks.length,
        color: AppColors.purple,
        icon: Icons.assignment_ind_rounded,
        initiallyExpanded: false,
        emptyMessage: 'No tasks assigned by manager.',
        children: [
          for (final (i, t) in _managerTasks.indexed)
            _managerTaskRow(t, i + 1),
        ],
      ),
      _simpleGroupCard(
        title: 'By self',
        count: unplannedTasks.length,
        color: AppColors.warning,
        icon: Icons.person_rounded,
        initiallyExpanded: false,
        emptyMessage: 'No unplanned tasks by self.',
        children: [
          for (final t in unplannedTasks)
            _completedTaskCard(
              taskName: asText(t['task']) ?? 'Unplanned Task',
              customerName: asText(t['customer']),
              categoryType: t['category_type'] as String?,
              timeStr: fmtTime(t['time']),
              metaStr: null,
              onTap: () {
                final taskId = t['id'];
                final partner = t['partner_id'];
                if (taskId is! int) {
                  if (partner is int) _openClient(partner);
                  return;
                }
                Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => TaskDocsScreen(
                        taskId: taskId,
                        title: '${t['task'] ?? 'Task'} · ${t['customer']}',
                        onOpenCustomer: partner is int ? () => _openClient(partner) : null)));
              },
            ),
        ],
      ),
    ];
  }

  Widget _completedTaskCard({
    required String taskName,
    String? customerName,
    String? categoryType,
    String? timeStr,
    String? metaStr,
    required VoidCallback onTap,
  }) {
    final cat = categoryType?.toLowerCase();
    final (typeLabel, typeColor) = switch (cat) {
      'lead' => ('Lead', AppColors.purple),
      'distributor' => ('Distributor', AppColors.warning),
      _ => ('Outlet', AppColors.primary),
    };

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border.withValues(alpha: 0.85)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(13),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: AppColors.success.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.check_rounded, color: AppColors.success, size: 20),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        taskName.isNotEmpty ? taskName : 'Completed Task',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 14.5,
                          color: AppColors.text,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: AppColors.success.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.check_circle_rounded, size: 12, color: AppColors.success),
                          SizedBox(width: 4),
                          Text(
                            'Done',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              color: AppColors.success,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                if (customerName != null && customerName.isNotEmpty && customerName != 'No customer') ...[
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: AppColors.border.withValues(alpha: 0.6)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.storefront_rounded, size: 15, color: AppColors.primary),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            customerName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: AppColors.text,
                            ),
                          ),
                        ),
                        if (categoryType != null && categoryType.isNotEmpty) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: typeColor.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              typeLabel,
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w800,
                                color: typeColor,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
                if ((timeStr != null && timeStr.isNotEmpty) || (metaStr != null && metaStr.isNotEmpty)) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      if (timeStr != null && timeStr.isNotEmpty) ...[
                        const Icon(Icons.access_time_rounded, size: 13, color: AppColors.muted),
                        const SizedBox(width: 4),
                        Text(
                          timeStr,
                          style: const TextStyle(fontSize: 12, color: AppColors.muted, fontWeight: FontWeight.w500),
                        ),
                        if (metaStr != null && metaStr.isNotEmpty) ...[
                          const SizedBox(width: 6),
                          const Text('·', style: TextStyle(color: AppColors.muted)),
                          const SizedBox(width: 6),
                        ],
                      ],
                      if (metaStr != null && metaStr.isNotEmpty)
                        Expanded(
                          child: Text(
                            metaStr,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 12, color: AppColors.muted),
                          ),
                        ),
                      const SizedBox(width: 4),
                      const Icon(Icons.chevron_right_rounded, size: 18, color: AppColors.muted),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _openManagerTaskCard(Map<String, dynamic> t, int number) {
    final customer = t['customer'] is Map ? (t['customer'] as Map)['name'] as String? : (t['customer'] as String?);
    final assignedBy = t['assigned_by'] as String?;
    final due = t['due'] != null ? 'Due ${t['due']}' : null;
    final meta = [
      if (assignedBy != null && assignedBy.isNotEmpty) 'Assigned by $assignedBy',
      if (due != null) due,
    ].join(' · ');

    final state = '${t['state']}';
    final stateLabel = state == 'in_progress' ? 'In progress' : 'To do';
    final stateColor = state == 'in_progress' ? AppColors.primary : AppColors.warning;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border.withValues(alpha: 0.85)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () async {
            final changed = await Navigator.of(context).push<bool>(
              MaterialPageRoute(builder: (_) => TaskDetailScreen(task: t, canAct: true)),
            );
            if (changed == true) _load();
          },
          child: Padding(
            padding: const EdgeInsets.all(13),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: AppColors.purple.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        '$number',
                        style: const TextStyle(color: AppColors.purple, fontWeight: FontWeight.w800, fontSize: 14),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        '${t['name']}',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 14.5,
                          color: AppColors.text,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                      decoration: BoxDecoration(
                        color: stateColor.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        stateLabel,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: stateColor,
                        ),
                      ),
                    ),
                  ],
                ),
                if (customer != null && customer.isNotEmpty && customer != 'No customer') ...[
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: AppColors.border.withValues(alpha: 0.6)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.storefront_rounded, size: 15, color: AppColors.primary),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            customer,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: AppColors.text,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                if (meta.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          meta,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 12, color: AppColors.muted),
                        ),
                      ),
                      const SizedBox(width: 4),
                      const Icon(Icons.chevron_right_rounded, size: 18, color: AppColors.muted),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _managerTaskRow(Map<String, dynamic> t, int number) {
    final state = '${t['state']}';
    if (state == 'done') {
      final customer = t['customer'] is Map ? (t['customer'] as Map)['name'] as String? : (t['customer'] as String?);
      final assignedBy = t['assigned_by'] as String?;
      final due = t['due'] != null ? 'Due ${t['due']}' : null;
      final meta = [
        if (assignedBy != null && assignedBy.isNotEmpty) 'Assigned by $assignedBy',
        if (due != null) due,
      ].join(' · ');
      return _completedTaskCard(
        taskName: '${t['name']}',
        customerName: customer,
        categoryType: t['category_type'] as String?,
        timeStr: null,
        metaStr: meta.isNotEmpty ? meta : null,
        onTap: () async {
          final changed = await Navigator.of(context).push<bool>(
            MaterialPageRoute(builder: (_) => TaskDetailScreen(task: t, canAct: true)),
          );
          if (changed == true) _load();
        },
      );
    }
    return _openManagerTaskCard(t, number);
  }

  Widget _simpleGroupCard({
    required String title,
    required int count,
    required Color color,
    required IconData icon,
    required List<Widget> children,
    String? emptyMessage,
    bool initiallyExpanded = false,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          initiallyExpanded: initiallyExpanded,
          tilePadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
          childrenPadding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
          leading: Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: 18),
          ),
          title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5)),
          trailing: Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 2.5),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Text(
              '$count',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5, color: color),
            ),
          ),
          children: children.isEmpty
              ? [
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    child: Center(
                      child: Text(
                        emptyMessage ?? 'No $title tasks.',
                        style: const TextStyle(color: AppColors.muted, fontSize: 13),
                      ),
                    ),
                  ),
                ]
              : children,
        ),
      ),
    );
  }

  /// Tab 2: Completed tasks grouped simply into Planned and Unplanned (which contains completed by manager and by self).
  List<Widget> _completedTasks() {
    final planned = _tasks.where(_isTaskPlanned).toList();
    final unplannedSelf = _tasks.where((t) => !_isTaskPlanned(t)).toList();
    final doneManagerTasks = _managerTasks.where((t) => t['state'] == 'done').toList();

    if (planned.isEmpty && unplannedSelf.isEmpty && doneManagerTasks.isEmpty) {
      return const [EmptyView(icon: Icons.task_alt_rounded, text: 'No task completed yet.')];
    }

    final unplannedTotal = doneManagerTasks.length + unplannedSelf.length;

    return [
      _simpleGroupCard(
        title: 'Planned',
        count: planned.length,
        color: AppColors.primary,
        icon: Icons.assignment_turned_in_rounded,
        initiallyExpanded: false,
        emptyMessage: 'No planned tasks completed.',
        children: [
          for (final t in planned)
            _completedTaskCard(
              taskName: asText(t['task']) ?? 'Planned Task',
              customerName: asText(t['customer']),
              categoryType: t['category_type'] as String?,
              timeStr: fmtTime(t['time']),
              metaStr: null,
              onTap: () {
                final taskId = t['id'];
                final partner = t['partner_id'];
                if (taskId is! int) {
                  if (partner is int) _openClient(partner);
                  return;
                }
                Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => TaskDocsScreen(
                        taskId: taskId,
                        title: '${t['task'] ?? 'Task'} · ${t['customer']}',
                        onOpenCustomer: partner is int ? () => _openClient(partner) : null)));
              },
            ),
        ],
      ),
      _simpleGroupCard(
        title: 'Unplanned',
        count: unplannedTotal,
        color: AppColors.warning,
        icon: Icons.task_alt_rounded,
        initiallyExpanded: false,
        emptyMessage: 'No unplanned tasks completed.',
        children: [
          for (final (i, t) in doneManagerTasks.indexed)
            _managerTaskRow(t, i + 1),
          for (final t in unplannedSelf)
            _completedTaskCard(
              taskName: asText(t['task']) ?? 'Unplanned Task',
              customerName: asText(t['customer']),
              categoryType: t['category_type'] as String?,
              timeStr: fmtTime(t['time']),
              metaStr: null,
              onTap: () {
                final taskId = t['id'];
                final partner = t['partner_id'];
                if (taskId is! int) {
                  if (partner is int) _openClient(partner);
                  return;
                }
                Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => TaskDocsScreen(
                        taskId: taskId,
                        title: '${t['task'] ?? 'Task'} · ${t['customer']}',
                        onOpenCustomer: partner is int ? () => _openClient(partner) : null)));
              },
            ),
        ],
      ),
    ];
  }

  String _planKey(Map<String, dynamic> plan) => '${(plan['beat'] as Map?)?['id'] ?? 'none'}';

  /// Does this customer belong to the beat that was chosen?
  bool _inBeat(Map<String, dynamic> client, List<Map<String, dynamic>> plans) {
    final route = client['route'] as Map?;
    if (_beat == 'none') return route == null;
    return route != null && '${route['id']}' == _beat;
  }

  /// Four figures first: how many beats are planned, the customers on them, how many were visited and the km.
  Widget _statBoxes(List<Map<String, dynamic>> plans) {
    num sum(String key) => plans.fold<num>(0, (a, p) => a + ((p[key] as num?) ?? 0));
    Widget box(IconData icon, Color tint, String value, String label) => Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 6),
            decoration: BoxDecoration(
              color: tint.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: tint.withValues(alpha: 0.25)),
            ),
            child: Column(children: [
              Icon(icon, size: 18, color: tint),
              const SizedBox(height: 6),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(value, style: TextStyle(fontWeight: FontWeight.w900, fontSize: 19, color: tint)),
              ),
              const SizedBox(height: 2),
              Text(label,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 10.5, color: AppColors.muted, fontWeight: FontWeight.w600, height: 1.15)),
            ]),
          ),
        );
    final km = sum('actual_km').toDouble();
    return Padding(
      padding: const EdgeInsets.only(top: 6, bottom: 12),
      child: Row(children: [
        box(Icons.alt_route_rounded, AppColors.primary, '${plans.length}', 'Planned beats'),
        const SizedBox(width: 8),
        box(Icons.storefront_rounded, AppColors.purple, '${sum('planned_count').toInt()}', 'Beat customers'),
        const SizedBox(width: 8),
        box(Icons.check_circle_rounded, AppColors.success, '${sum('completed_count').toInt()}', 'Visited'),
        const SizedBox(width: 8),
        box(Icons.route_rounded, AppColors.warning, km.toStringAsFixed(1), 'km'),
      ]),
    );
  }

  /// Two filters in the style of the client filter: the beat, and the status of the visit.
  Widget _filters(List<Map<String, dynamic>> plans) {
    Widget pill(String value, List<DropdownMenuItem<String>> items, ValueChanged<String?> onChanged) => Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: AppColors.border),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: value,
                isExpanded: true,
                icon: const Icon(Icons.keyboard_arrow_down_rounded, color: AppColors.primary),
                style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800, color: AppColors.primary),
                items: items,
                onChanged: onChanged,
              ),
            ),
          ),
        );
    final known = {for (final p in plans) _planKey(p)};
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: SizedBox(
        height: 46,
        child: Row(children: [
          pill(
            known.contains(_beat) ? _beat! : 'all',
            [
              const DropdownMenuItem(value: 'all', child: Text('All beats')),
              for (final p in plans)
                DropdownMenuItem(
                  value: _planKey(p),
                  child: Text(asText((p['beat'] as Map?)?['name']) ?? 'Without a beat',
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                ),
            ],
            (v) => setState(() => _beat = v == 'all' ? null : v),
          ),
          const SizedBox(width: 10),
          pill(
            _filter == 'planned' ? 'pending' : _filter,
            const [
              DropdownMenuItem(value: 'all', child: Text('All status')),
              DropdownMenuItem(value: 'visited', child: Text('Visited')),
              DropdownMenuItem(value: 'pending', child: Text('Pending')),
              DropdownMenuItem(value: 'cancelled', child: Text('Cancelled')),
              DropdownMenuItem(value: 'offsite', child: Text('Offsite')),
            ],
            (v) => setState(() => _filter = v ?? 'all'),
          ),
        ]),
      ),
    );
  }

  /// A visit added to the day (not on the plan): its place in the list, distance and time.
  Widget _addedTile(Map<String, dynamic> row, int number) {
    final visit = row['_visit'] as Map;
    final state = visit['state'];
    final metres = metresTo(_here, row);
    final extraInfo = [
      state == 'added' ? 'Planned visit' : 'Added visit',
      if (metres != null) fmtDistance(metres),
      if ((row['_visits'] as int? ?? 1) > 1) '${row['_visits']} visits · last',
      if (state != 'added') '${fmtTime(visit['check_in_at'])}–${fmtTime(visit['check_out_at'])}',
    ].join(' · ');
    return _tileRow(
      color: AppColors.purple,
      number: '$number',
      name: '${row['name']}',
      address: asText(row['address']),
      extraInfo: extraInfo.isNotEmpty ? extraInfo : null,
      categoryType: row['category_type'] as String? ?? (row['is_distributor'] == true ? 'distributor' : 'outlet'),
      // Added and waiting, at the client now, or visited.
      badge: StatusBadge(switch (state) { 'added' => 'planned', 'ongoing' => 'ongoing', _ => 'visited' }),
      onTap: () => _openClient(row['id'] as int),
    );
  }

  /// One customer row. Name, contact type + planned tag on same row, full 2-line address, distance/route.
  Widget _tileRow({
    required Color color,
    required String number,
    required String name,
    required String? address,
    required String? extraInfo,
    required Widget badge,
    required VoidCallback onTap,
    Widget? menu,
    String? categoryType,
  }) {
    final cat = categoryType?.toLowerCase();
    final (typeLabel, typeColor) = switch (cat) {
      'lead' => ('Lead', AppColors.purple),
      'distributor' => ('Distributor', AppColors.warning),
      _ => ('Outlet', AppColors.primary),
    };
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border.withValues(alpha: 0.85)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(13),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  radius: 18,
                  backgroundColor: color.withValues(alpha: 0.14),
                  child: Text(number, style: TextStyle(color: color, fontWeight: FontWeight.w800, fontSize: 13)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Text(
                              name,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: AppColors.text),
                            ),
                          ),
                          if (menu != null)
                            SizedBox(
                              width: 24,
                              height: 24,
                              child: menu,
                            ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      // Contact type and planned tag on SAME row
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2.5),
                            decoration: BoxDecoration(
                              color: typeColor.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              typeLabel,
                              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: typeColor),
                            ),
                          ),
                          const SizedBox(width: 6),
                          badge,
                        ],
                      ),
                      if (address != null && address.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Padding(
                              padding: EdgeInsets.only(top: 2),
                              child: Icon(Icons.location_on_outlined, size: 14, color: AppColors.muted),
                            ),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                address,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 12.5, color: AppColors.muted, height: 1.3),
                              ),
                            ),
                          ],
                        ),
                      ],
                      if (extraInfo != null && extraInfo.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            const Icon(Icons.near_me_outlined, size: 13, color: AppColors.muted),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                extraInfo,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 11.5, color: AppColors.muted, fontWeight: FontWeight.w500),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// [number] is the place in today's nearest-first list; other days show the planned sequence.
  Widget _clientTile(Map<String, dynamic> client, {required bool showRoute, int? number}) {
    final visitStatus = client['visit_status'] as String?;
    final status = visitStatus == 'ongoing' ? 'ongoing' : (client['plan_status'] as String? ?? 'planned');
    final color = switch (status) {
      'visited' => AppColors.success,
      'missed' => AppColors.danger,
      'cancelled' => AppColors.warning,
      'ongoing' => AppColors.sky,
      _ => AppColors.primary,
    };
    final routeName = showRoute ? asText((client['route'] as Map?)?['name']) : null;
    final distance = number != null
        ? fmtDistance(metresTo(_here, client))
        : (client['distance_m'] != null ? fmtDistance(client['distance_m'] as num?) : null);
    final extraInfo = [routeName, distance].whereType<String>().where((s) => s.isNotEmpty).join(' · ');
    final address = asText(client['address']);
    return _tileRow(
      color: color,
      number: '${number ?? client['sequence']}',
      name: '${client['name']}',
      address: (address == null || address.isEmpty) ? lastVisitLabel(client) : address,
      extraInfo: extraInfo.isNotEmpty ? extraInfo : null,
      badge: StatusBadge(status),
      categoryType: client['category_type'] as String? ?? (client['is_distributor'] == true ? 'distributor' : 'outlet'),
      // A planned visit that has not started can be cancelled; a cancelled one planned again.
      menu: (_isToday && (status == 'planned' || status == 'cancelled'))
          ? PopupMenuButton<String>(
              tooltip: 'More',
              padding: EdgeInsets.zero,
              iconSize: 20,
              icon: const Icon(Icons.more_vert_rounded),
              onSelected: (v) => _cancelVisit(client, undo: v == 'undo'),
              itemBuilder: (_) => [
                if (status == 'planned') const PopupMenuItem(value: 'cancel', child: Text('Cancel this visit')),
                if (status == 'cancelled') const PopupMenuItem(value: 'undo', child: Text('Plan it again')),
              ],
            )
          : null,
      onTap: () => _openClient(client['id'] as int),
    );
  }
}
