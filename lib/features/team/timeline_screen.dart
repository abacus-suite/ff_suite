import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../core/format.dart';
import '../../core/services.dart';
import '../../core/theme.dart';
import '../../widgets/group_kit.dart';
import '../../widgets/map.dart';
import '../../widgets/skeleton.dart';
import '../beat/plan_beat_screen.dart';
import '../reports/summary_drill.dart';

/// One team member's day, as a profile: where they are, what they did, the route they took and the work they recorded.
class TimelineScreen extends StatefulWidget {
  const TimelineScreen({super.key, required this.employeeId, required this.employeeName});

  final int employeeId;
  final String employeeName;

  @override
  State<TimelineScreen> createState() => _TimelineScreenState();
}

class _TimelineScreenState extends State<TimelineScreen> {
  DateTime _day = DateTime.now();
  Map<String, dynamic>? _data;
  String? _error;
  bool _loading = true;
  String _tab = 'activity';

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
      final data = await Services.api.get('/api/v1/team/${widget.employeeId}/timeline', query: {'date': fmtDate(_day)})
          as Map<String, dynamic>;
      if (mounted) setState(() => _data = data);
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

  bool get _isToday => fmtDate(_day) == fmtDate(DateTime.now());

  List<Map<String, dynamic>> _list(String key) => ((_data?[key] as List?) ?? []).cast<Map<String, dynamic>>();

  IconData _icon(String kind) => switch (kind) {
        'order' || 'demand' => Icons.shopping_bag_rounded,
        'collection' || 'payment' => Icons.payments_rounded,
        'expense' => Icons.receipt_long_rounded,
        'return' => Icons.assignment_return_rounded,
        'stock' => Icons.inventory_2_rounded,
        'form' => Icons.assignment_rounded,
        'task' => Icons.task_alt_rounded,
        _ => Icons.bolt_rounded,
      };

  Color _tone(String kind) => switch (kind) {
        'order' || 'demand' => AppColors.primary,
        'collection' || 'payment' => AppColors.success,
        'expense' => AppColors.warning,
        'return' => AppColors.danger,
        _ => AppColors.purple,
      };

  // ------------------------------------------------------------------ pieces
  Widget _hero() {
    final data = _data!;
    final attendance = _list('attendance');
    final open = attendance.where((a) => a['check_out'] == null).firstOrNull;
    final visits = _list('visits');
    final ongoing = visits.where((v) => v['check_out_at'] == null).firstOrNull;
    final plan = data['plan'] as Map<String, dynamic>?;
    final first = attendance.isNotEmpty ? attendance.first : null;
    final working = open != null;
    final colour = working ? AppColors.success : (attendance.isNotEmpty ? AppColors.primary : AppColors.muted);
    final status = working ? 'Checked in' : (attendance.isNotEmpty ? 'Checked out' : 'Not in');
    Widget stat(String value, String label) => Expanded(
          child: Column(children: [
            FittedBox(child: Text(value, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 18))),
            const SizedBox(height: 2),
            Text(label, style: const TextStyle(color: Colors.white70, fontSize: 11)),
          ]),
        );
    final activity = _list('activity');
    final sales = activity.where((a) => a['kind'] == 'order' || a['kind'] == 'demand').fold<double>(0, (s, a) => s + ((a['amount'] as num?) ?? 0));
    final collected = activity.where((a) => a['kind'] == 'collection').fold<double>(0, (s, a) => s + ((a['amount'] as num?) ?? 0));
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
            colors: [Color(0xFF1B3A7A), Color(0xFF2563EB), Color(0xFF06B6D4)], begin: Alignment.topLeft, end: Alignment.bottomRight),
        borderRadius: BorderRadius.circular(26),
        boxShadow: [BoxShadow(color: const Color(0xFF2563EB).withValues(alpha: 0.28), blurRadius: 22, offset: const Offset(0, 10))],
      ),
      child: Column(children: [
        Row(children: [
          Stack(clipBehavior: Clip.none, children: [
            CircleAvatar(
              radius: 30,
              backgroundColor: Colors.white,
              child: Text(widget.employeeName.isEmpty ? '?' : widget.employeeName[0].toUpperCase(),
                  style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 26, color: AppColors.primary)),
            ),
            Positioned(
              right: -1,
              bottom: -1,
              child: Container(
                  width: 17,
                  height: 17,
                  decoration: BoxDecoration(color: colour, shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 3))),
            ),
          ]),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(widget.employeeName, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 19)),
              const SizedBox(height: 3),
              Text(
                  '$status${first != null ? ' · in ${fmtTime(first['check_in'])}' : ''}${open == null && attendance.isNotEmpty ? ' · out ${fmtTime(attendance.last['check_out'])}' : ''}',
                  style: const TextStyle(color: Colors.white70, fontSize: 12.5)),
              if (ongoing != null)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(20)),
                    child: Text('At ${(ongoing['client'] as Map)['name']}',
                        maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 12)),
                  ),
                ),
            ]),
          ),
        ]),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.symmetric(vertical: 11),
          decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(16)),
          child: Row(children: [
            stat('${((data['distance_km'] as num?) ?? 0).toStringAsFixed(1)} km', 'Travelled'),
            stat('${visits.length}', 'Visits'),
            stat(plan != null ? '${plan['completed_count']}/${plan['planned_count']}' : '-', 'Beat done'),
            stat(fmtCompactMoney(sales), 'Orders'),
            stat(fmtCompactMoney(collected), 'Collected'),
          ]),
        ),
      ]),
    );
  }

  Widget _dateBar() => Container(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18)),
        child: Row(children: [
          IconButton(onPressed: () => _shift(-1), icon: const Icon(Icons.chevron_left_rounded)),
          Expanded(
            child: TextButton.icon(
              onPressed: () async {
                final today = DateTime.now();
                final picked = await showDatePicker(
                    context: context, initialDate: _day, firstDate: today.subtract(const Duration(days: 90)), lastDate: today);
                if (picked != null) {
                  setState(() => _day = picked);
                  _load();
                }
              },
              icon: const Icon(Icons.calendar_today_rounded, size: 17),
              label: Text(_isToday ? 'Today · ${prettyDay(_day)}' : prettyDay(_day), style: const TextStyle(fontWeight: FontWeight.w800)),
            ),
          ),
          IconButton(onPressed: _isToday ? null : () => _shift(1), icon: const Icon(Icons.chevron_right_rounded)),
        ]),
      );

  Widget _actions() {
    Widget button(IconData icon, String label, Color c, VoidCallback onTap) => Expanded(
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: onTap,
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 4),
              padding: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(color: c.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(16)),
              child: Column(children: [Icon(icon, color: c), const SizedBox(height: 5), Text(label, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12))]),
            ),
          ),
        );
    final today = DateUtils.dateOnly(DateTime.now());
    return Row(children: [
      button(Icons.bar_chart_rounded, 'Reports', AppColors.primary, () => Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => EmployeeReportScreen(memberId: '${widget.employeeId}', name: widget.employeeName, start: DateTime(today.year, today.month, 1), end: today)))),
      button(Icons.event_note_rounded, 'Beat plan', AppColors.purple, () => Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => PlannedDaysScreen(member: '${widget.employeeId}', memberName: widget.employeeName, start: today)))),
      button(Icons.fullscreen_rounded, 'Full map', AppColors.success, _openMap),
    ]);
  }

  (List<LatLng>, List<(Map<String, dynamic>, LatLng)>) _geo() {
    final points = _list('points').map((p) => LatLng((p['lat'] as num).toDouble(), (p['lng'] as num).toDouble())).toList();
    final visitPoints = _list('visits')
        .where((v) => (v['lat'] as num? ?? 0) != 0)
        .map((v) => (v, LatLng((v['lat'] as num).toDouble(), (v['lng'] as num).toDouble())))
        .toList();
    return (points, visitPoints);
  }

  Widget _mapWidget({double zoom = 14}) {
    final (points, visitPoints) = _geo();
    final all = [...points, ...visitPoints.map((e) => e.$2)];
    if (all.isEmpty) {
      return const Center(child: Text('No location data for this day', style: TextStyle(color: AppColors.muted)));
    }
    return AppMap(
      fitPoints: all,
      center: all.first,
      zoom: zoom,
      children: [
        PolylineLayer(polylines: travelPath(points)),
        MarkerLayer(markers: [
          if (points.isNotEmpty) Marker(point: points.first, child: const Icon(Icons.trip_origin_rounded, color: AppColors.success)),
          if (points.isNotEmpty)
            Marker(
              point: points.last,
              width: MapPin.size.width,
              height: MapPin.size.height,
              alignment: Alignment.topCenter,
              child: const MapPin(color: AppColors.danger, icon: Icons.navigation_rounded),
            ),
          for (final (visit, point) in visitPoints)
            Marker(
              point: point,
              width: MapPinWithLabel.size.width,
              height: MapPinWithLabel.size.height,
              alignment: Alignment.topCenter,
              child: MapPinWithLabel(
                label: '${(visit['client'] as Map)['name']}',
                color: visit['inside_geofence'] == false ? AppColors.warning : AppColors.purple,
                icon: Icons.storefront_rounded,
              ),
            ),
        ]),
      ],
    );
  }

  void _openMap() {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => Scaffold(appBar: AppBar(title: Text('${widget.employeeName} · ${prettyDay(_day)}')), body: _mapWidget()),
    ));
  }

  Widget _mapCard() => Container(
        height: 210,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(22), color: Colors.white),
        child: Stack(children: [
          Positioned.fill(child: IgnorePointer(child: _mapWidget(zoom: 13))),
          Positioned(
            right: 8,
            top: 8,
            child: Material(
              color: Colors.white,
              shape: const CircleBorder(),
              elevation: 2,
              child: IconButton(onPressed: _openMap, icon: const Icon(Icons.open_in_full_rounded, size: 19)),
            ),
          ),
        ]),
      );

  Widget _activityTab() {
    final rows = _list('activity');
    final visits = _list('visits');
    // One timeline: the visits and the work recorded, in the order they happened.
    final items = <(DateTime?, Widget)>[
      for (final v in visits) (parseServerTime(v['check_in_at']), _visitTile(v)),
      for (final a in rows) (parseServerTime(a['at']), _activityTile(a)),
    ]..sort((a, b) => (a.$1 ?? DateTime(2000)).compareTo(b.$1 ?? DateTime(2000)));
    if (items.isEmpty) {
      return const Padding(padding: EdgeInsets.all(30), child: Center(child: Text('Nothing recorded this day.', style: TextStyle(color: AppColors.muted))));
    }
    return Column(children: [for (final item in items) item.$2]);
  }

  Widget _row({required IconData icon, required Color colour, required String title, required String subtitle, String? trailing, String? time}) =>
      Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18)),
        child: Row(children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(color: colour.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(14)),
            child: Icon(icon, color: colour, size: 21),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800)),
              if (subtitle.isNotEmpty) Text(subtitle, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: AppColors.muted)),
            ]),
          ),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            if (trailing != null) Text(trailing, style: const TextStyle(fontWeight: FontWeight.w900)),
            if (time != null) Text(time, style: const TextStyle(fontSize: 11.5, color: AppColors.muted)),
          ]),
        ]),
      );

  Widget _visitTile(Map<String, dynamic> v) {
    final outside = v['inside_geofence'] == false;
    final open = v['check_out_at'] == null;
    return _row(
      icon: Icons.storefront_rounded,
      colour: outside ? AppColors.warning : AppColors.purple,
      title: '${(v['client'] as Map)['name']}',
      subtitle: 'Visit · ${fmtTime(v['check_in_at'])} to ${open ? 'now' : fmtTime(v['check_out_at'])}${outside ? ' · outside geofence' : ''}',
      trailing: open ? 'At client' : null,
      time: fmtTime(v['check_in_at']),
    );
  }

  Widget _activityTile(Map<String, dynamic> a) {
    final kind = '${a['kind']}';
    final partner = (a['partner'] as Map?)?['name'];
    return _row(
      icon: _icon(kind),
      colour: _tone(kind),
      title: '${a['title']}',
      subtitle: [if (partner != null) '$partner', if ('${a['detail']}'.isNotEmpty) '${a['detail']}'].join(' · '),
      trailing: a['amount'] != null ? fmtMoney(a['amount'] as num?, null) : null,
      time: fmtTime(a['at']),
    );
  }

  Widget _punchesTab() {
    final rows = _list('attendance');
    if (rows.isEmpty) {
      return const Padding(padding: EdgeInsets.all(30), child: Center(child: Text('No check-ins this day.', style: TextStyle(color: AppColors.muted))));
    }
    return Column(children: [
      for (final a in rows)
        _row(
          icon: Icons.fingerprint_rounded,
          colour: a['check_out'] == null ? AppColors.success : AppColors.primary,
          title: '${fmtTime(a['check_in'])} to ${a['check_out'] == null ? 'now' : fmtTime(a['check_out'])}',
          subtitle: [
            if (a['in_address'] != null) '${a['in_address']}',
            if ((a['late_minutes'] as num? ?? 0) > 0) '${a['late_minutes']} min late',
            if (a['odometer_km'] != null) '${a['odometer_km']} km by the meter',
          ].join(' · '),
          trailing: '${((a['worked_hours'] as num?) ?? 0).toStringAsFixed(1)} h',
        ),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: Text(widget.employeeName)),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 40),
          children: [
            _dateBar(),
            const SizedBox(height: 12),
            if (_loading && _data == null) const Padding(padding: EdgeInsets.all(40), child: LoadingView()),
            if (_error != null && _data == null) Padding(padding: const EdgeInsets.all(16), child: Text(_error!)),
            if (_data != null) ...[
              _hero(),
              const SizedBox(height: 12),
              _actions(),
              const SizedBox(height: 12),
              _mapCard(),
              const SizedBox(height: 14),
              SegmentedButton<String>(
                showSelectedIcon: false,
                segments: [
                  ButtonSegment(value: 'activity', label: Text('Day (${_list('visits').length + _list('activity').length})')),
                  ButtonSegment(value: 'punches', label: Text('Check-ins (${_list('attendance').length})')),
                ],
                selected: {_tab},
                onSelectionChanged: (v) => setState(() => _tab = v.first),
              ),
              const SizedBox(height: 12),
              if (_tab == 'activity') _activityTab() else _punchesTab(),
            ],
          ],
        ),
      ),
    );
  }
}

String fmtCompactMoney(num v) {
  final n = v.toDouble();
  if (n >= 10000000) return '${(n / 10000000).toStringAsFixed(1)}Cr';
  if (n >= 100000) return '${(n / 100000).toStringAsFixed(1)}L';
  if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}k';
  return n.toStringAsFixed(0);
}
