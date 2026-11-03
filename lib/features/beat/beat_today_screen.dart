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
  // Only today's plan is shown: no other day can be opened from here.
  final DateTime _day = DateTime.now();
  late String _filter = widget.filter;

  /// The beat the list below is narrowed to (its id, or 'none' for the plan with no beat); null shows every beat.
  String? _beat;
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
        _ => status != 'visited' && status != 'cancelled' && status != 'skipped',
      };
    }).toList();
    final adhoc = ((data['adhoc_visits'] as List?) ?? []).cast<Map<String, dynamic>>();
    if (_isToday) return _todayContent(plans, clients, adhoc, label);
    return [
      _statBoxes(plans),
      if (plans.isEmpty)
        EmptyView(icon: Icons.event_busy_rounded,
            text: 'No $label planned for this day.\nUse "Add a Visit" to visit anyone.'),
      _filters(plans),
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
    final every = [
      for (final visit in adhoc)
        if (_filter == 'all' ||
            (_filter == 'visited' && visit['state'] != 'ongoing' && '${visit['visit_type']}' != 'offsite') ||
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
    final visited = {for (final v in adhoc) (v['client'] as Map?)?['id']};
    final planned = {for (final c in ((_data?['clients'] as List?) ?? []).cast<Map>()) c['id']};
    final waiting = [
      if (_filter == 'all' || _filter == 'pending' || _filter == 'planned')
        for (final a in _added)
          if (!visited.contains(a['id']) && !planned.contains(a['id'])) {...a, '_visit': const {'state': 'added'}},
    ];
    // Visits added by hand belong to no beat: they are left out while one beat is chosen.
    final rows = nearestFirst([...clients, if (_beat == null) ...added, if (_beat == null) ...waiting], _here);
    return [
      _statBoxes(plans),
      if (plans.isEmpty && rows.isEmpty && _filter == 'all')
        EmptyView(icon: Icons.event_busy_rounded,
            text: 'No $label planned for this day.\nUse "Add a Visit" to visit anyone.'),
      _filters(plans),
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
    // A visit made away from the outlet (offsite) is not a visit to it: it is not shown as Visited.
    final offsite = state != 'added' && state != 'ongoing' && '${visit['visit_type']}' == 'offsite';
    final details = [
      // Waiting to be saved in today's plan, it reads as planned like any other stop.
      state == 'added' ? 'Planned' : 'Added visit',
      if (offsite) 'Offsite',
      if (metres != null) fmtDistance(metres),
      if ((row['_visits'] as int? ?? 1) > 1) '${row['_visits']} visits · last',
      if (state != 'added') '${fmtTime(visit['check_in_at'])}–${fmtTime(visit['check_out_at'])}',
    ].join(' · ');
    return _tileRow(
      color: AppColors.purple,
      number: '$number',
      name: '${row['name']}',
      details: details,
      // Added and waiting, at the client now, or visited.
      badge: offsite
          ? const StatusBadge('cancelled', label: 'Offsite')
          : StatusBadge(switch (state) { 'added' => 'planned', 'ongoing' => 'ongoing', _ => 'visited' }),
      onTap: () => _openClient(row['id'] as int),
    );
  }

  /// One customer row. The name takes the room that is left, and the status badge and the menu sit in
  /// columns of their own, so they line up from one row to the next.
  Widget _tileRow({
    required Color color,
    required String number,
    required String name,
    required String details,
    required Widget badge,
    required VoidCallback onTap,
    Widget? menu,
  }) {
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
          child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
            CircleAvatar(
              backgroundColor: color.withValues(alpha: 0.14),
              child: Text(number, style: TextStyle(color: color, fontWeight: FontWeight.w800)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                Text(name, maxLines: 2, overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                const SizedBox(height: 3),
                Text(details, maxLines: 2, overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12.5, color: AppColors.muted)),
              ]),
            ),
            const SizedBox(width: 8),
            SizedBox(width: 84, child: Center(child: badge)),
            SizedBox(width: 36, child: menu),
          ]),
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
    return _tileRow(
      color: color,
      number: '${number ?? client['sequence']}',
      name: '${client['name']}',
      details: details.isEmpty ? lastVisitLabel(client) : details,
      badge: StatusBadge(status),
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
