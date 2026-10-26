import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../../core/format.dart';
import '../../core/geo.dart';
import '../../core/services.dart';
import '../../core/theme.dart';
import '../../widgets/common.dart';
import 'add_visit_screen.dart';
import 'added_visits.dart';
import 'plan_day_screen.dart';
import '../clients/client_detail_screen.dart';
import '../clients/clients_screen.dart';

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
  DateTime _day = DateTime.now();
  late String _filter = widget.filter;
  Map<String, dynamic>? _data;
  bool _loading = true;
  String? _error;

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
      final data = await Services.api.get('/api/v1/beat/today', query: {
        'date': fmtDate(_day),
        if (pos != null) 'lat': pos.latitude,
        if (pos != null) 'lng': pos.longitude,
      }) as Map<String, dynamic>;
      if (mounted) setState(() => (_data = data, _error = null));
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _shift(int days) {
    setState(() => _day = _day.add(Duration(days: days)));
    _load();
  }

  Future<void> _pickDay() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _day,
      firstDate: now.subtract(const Duration(days: 60)),
      lastDate: now.add(const Duration(days: 60)),
    );
    if (picked != null) {
      setState(() => _day = picked);
      _load();
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
      for (final v in ((data?['adhoc_visits'] as List?) ?? []).cast<Map>()) (v['client'] as Map?)?['id'],
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
        actions: [
          // Which of the day's customers to list: All, Visited, Pending or Cancelled.
          Container(
            margin: const EdgeInsets.symmetric(vertical: 8),
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AppColors.border),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: _filter == 'planned' ? 'pending' : _filter,
                isDense: true,
                style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: AppColors.primary),
                items: const [
                  DropdownMenuItem(value: 'all', child: Text('All')),
                  DropdownMenuItem(value: 'visited', child: Text('Visited')),
                  DropdownMenuItem(value: 'pending', child: Text('Pending')),
                  DropdownMenuItem(value: 'cancelled', child: Text('Cancelled')),
                ],
                onChanged: (v) => setState(() => _filter = v ?? 'all'),
              ),
            ),
          ),
          IconButton(
            tooltip: 'Plan a day',
            onPressed: () async {
              final saved = await Navigator.of(context)
                  .push<bool>(MaterialPageRoute(builder: (_) => const PlanDayScreen()));
              if (saved == true) _load();
            },
            icon: const Icon(Icons.edit_calendar_rounded),
          ),
          IconButton(onPressed: _load, icon: const Icon(Icons.refresh_rounded)),
        ],
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
            _dateBar(),
            if (_loading) const LinearProgressIndicator(),
            if (_error != null && _data == null) ErrorView(message: _error!, onRetry: _load),
            if (_data != null) ..._content(_data!, label),
          ],
        ),
      ),
    );
  }

  Widget _dateBar() {
    final isToday = fmtDate(_day) == fmtDate(DateTime.now());
    return Card(
      child: Row(
        children: [
          IconButton(onPressed: () => _shift(-1), icon: const Icon(Icons.chevron_left_rounded)),
          Expanded(
            child: InkWell(
              onTap: _pickDay,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Column(
                  children: [
                    Text(isToday ? 'Today' : _weekdayNames[_day.weekday - 1],
                        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                    Text('${_day.day} ${monthNames[_day.month - 1]} ${_day.year}',
                        style: const TextStyle(color: AppColors.muted, fontSize: 12)),
                  ],
                ),
              ),
            ),
          ),
          IconButton(onPressed: () => _shift(1), icon: const Icon(Icons.chevron_right_rounded)),
        ],
      ),
    );
  }

  List<Widget> _content(Map<String, dynamic> data, String label) {
    final plans = ((data['plans'] as List?) ?? []).cast<Map<String, dynamic>>();
    final every = ((data['clients'] as List?) ?? []).cast<Map<String, dynamic>>();
    final clients = every.where((c) {
      if (_filter == 'all') return true;
      final status = c['visit_status'] == 'done' ? 'visited' : (c['plan_status'] as String? ?? 'planned');
      return switch (_filter) {
        'visited' => status == 'visited',
        'cancelled' => status == 'cancelled',
        _ => status != 'visited' && status != 'cancelled' && status != 'skipped',
      };
    }).toList();
    final adhoc = ((data['adhoc_visits'] as List?) ?? []).cast<Map<String, dynamic>>();
    if (_isToday) return _todayContent(plans, clients, adhoc, label);
    return [
      if (plans.isEmpty)
        EmptyView(icon: Icons.event_busy_rounded,
            text: 'No $label planned for this day.\nUse "Add a Visit" to visit anyone.'),
      if (_filter == 'all') for (final plan in plans) _planCard(plan),
      if (_filter != 'all')
        Padding(
          padding: const EdgeInsets.fromLTRB(0, 10, 0, 0),
          child: Align(
            alignment: Alignment.centerLeft,
            child: InputChip(
              label: Text('Showing ${_filter[0].toUpperCase()}${_filter.substring(1)} (${clients.length})'),
              onDeleted: () => setState(() => _filter = 'all'),
            ),
          ),
        ),
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
    // An added visit counts as pending while it runs and as visited once it is closed.
    final added = [
      for (final visit in adhoc)
        if (_filter == 'all' ||
            (_filter == 'visited' && visit['state'] != 'ongoing') ||
            ((_filter == 'pending' || _filter == 'planned') && visit['state'] == 'ongoing'))
          {...(visit['client'] as Map).cast<String, dynamic>(), '_visit': visit},
    ];
    // Added with "Add a Visit" and not visited yet: pending, until the server has the visit.
    final visited = {for (final v in adhoc) (v['client'] as Map?)?['id']};
    final planned = {for (final c in ((_data?['clients'] as List?) ?? []).cast<Map>()) c['id']};
    final waiting = [
      if (_filter == 'all' || _filter == 'pending' || _filter == 'planned')
        for (final a in _added)
          if (!visited.contains(a['id']) && !planned.contains(a['id'])) {...a, '_visit': const {'state': 'added'}},
    ];
    final rows = nearestFirst([...clients, ...added, ...waiting], _here);
    return [
      if (plans.isEmpty && rows.isEmpty && _filter == 'all')
        EmptyView(icon: Icons.event_busy_rounded,
            text: 'No $label planned for this day.\nUse "Add a Visit" to visit anyone.'),
      if (_filter == 'all') for (final plan in plans) _planCard(plan),
      if (_filter != 'all')
        Padding(
          padding: const EdgeInsets.fromLTRB(0, 10, 0, 0),
          child: Align(
            alignment: Alignment.centerLeft,
            child: InputChip(
              label: Text('Showing ${_filter[0].toUpperCase()}${_filter.substring(1)} (${rows.length})'),
              onDeleted: () => setState(() => _filter = 'all'),
            ),
          ),
        ),
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
    ];
  }

  /// A visit added to the day (not on the plan): its place in the list, distance and time.
  Widget _addedTile(Map<String, dynamic> row, int number) {
    final visit = row['_visit'] as Map;
    final state = visit['state'];
    final metres = metresTo(_here, row);
    final details = [
      'Added visit',
      if (metres != null) fmtDistance(metres),
      if (state != 'added') '${fmtTime(visit['check_in_at'])}–${fmtTime(visit['check_out_at'])}',
    ].join(' · ');
    return Card(
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: AppColors.purple.withValues(alpha: 0.14),
          child: Text('$number', style: const TextStyle(color: AppColors.purple, fontWeight: FontWeight.w800)),
        ),
        title: Text('${row['name']}', style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(details, maxLines: 2, overflow: TextOverflow.ellipsis),
        // Added and waiting, at the client now, or visited.
        trailing: StatusBadge(switch (state) { 'added' => 'added', 'ongoing' => 'ongoing', _ => 'visited' }),
        onTap: () => _openClient(row['id'] as int),
      ),
    );
  }

  Widget _planCard(Map<String, dynamic> plan) {
    final pct = ((plan['completion_pct'] as num?) ?? 0).toDouble();
    final status = switch (plan['status']) {
      'done' => 'visited',
      'in_progress' => 'ongoing',
      'missed' => 'missed',
      _ => 'planned',
    };
    Widget count(IconData icon, Color color, String text) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [Icon(icon, size: 16, color: color), const SizedBox(width: 4), Text(text)],
        );
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text('${(plan['beat'] as Map?)?['name'] ?? ''}',
                      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                ),
                StatusBadge(status, label: status == 'ongoing' ? 'In progress' : null),
              ],
            ),
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: pct / 100,
                minHeight: 8,
                backgroundColor: AppColors.border,
                valueColor: const AlwaysStoppedAnimation(AppColors.teal),
              ),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 14,
              runSpacing: 6,
              children: [
                count(Icons.flag_rounded, AppColors.primary, '${plan['planned_count']} planned'),
                count(Icons.check_circle_rounded, AppColors.success, '${plan['completed_count']} visited'),
                if ((plan['missed_count'] as num? ?? 0) > 0)
                  count(Icons.cancel_rounded, AppColors.danger, '${plan['missed_count']} missed'),
                if ((plan['adhoc_count'] as num? ?? 0) > 0)
                  count(Icons.bolt_rounded, AppColors.purple, '${plan['adhoc_count']} adhoc'),
                count(Icons.route_rounded, AppColors.muted, '${plan['actual_km']} km'),
              ],
            ),
          ],
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
    final details = [
      if (showRoute) asText((client['route'] as Map?)?['name']),
      asText(client['address']),
      if (number != null)
        fmtDistance(metresTo(_here, client))
      else if (client['distance_m'] != null)
        fmtDistance(client['distance_m'] as num?),
    ].whereType<String>().where((s) => s.isNotEmpty).join(' · ');
    return Card(
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: color.withValues(alpha: 0.14),
          child: Text('${number ?? client['sequence']}', style: TextStyle(color: color, fontWeight: FontWeight.w800)),
        ),
        title: Text('${client['name']}', style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(details.isEmpty ? lastVisitLabel(client) : details, maxLines: 2, overflow: TextOverflow.ellipsis),
        trailing: StatusBadge(status),
        onTap: () => _openClient(client['id'] as int),
      ),
    );
  }
}
