import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../core/format.dart';
import '../../core/services.dart';
import '../../core/theme.dart';
import '../../widgets/map.dart';

/// Route replay of one team member for one day, with client visits.
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
  bool _loading = false;

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
      final data = await Services.api.get('/api/v1/team/${widget.employeeId}/timeline',
          query: {'date': fmtDate(_day)}) as Map<String, dynamic>;
      setState(() => _data = data);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _shift(int days) {
    setState(() => _day = _day.add(Duration(days: days)));
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final today = DateTime.now();
    final isToday = fmtDate(_day) == fmtDate(today);
    return Scaffold(
      appBar: AppBar(title: Text(widget.employeeName)),
      body: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              IconButton(onPressed: () => _shift(-1), icon: const Icon(Icons.chevron_left)),
              TextButton(
                onPressed: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: _day,
                    firstDate: today.subtract(const Duration(days: 90)),
                    lastDate: today,
                  );
                  if (picked != null) {
                    setState(() => _day = picked);
                    _load();
                  }
                },
                child: Text(isToday ? 'Today' : fmtDate(_day)),
              ),
              IconButton(onPressed: isToday ? null : () => _shift(1), icon: const Icon(Icons.chevron_right)),
            ],
          ),
          if (_loading) const LinearProgressIndicator(),
          if (_error != null) Padding(padding: const EdgeInsets.all(16), child: Text(_error!)),
          if (_data != null) ..._content(_data!),
        ],
      ),
    );
  }

  List<Widget> _content(Map<String, dynamic> data) {
    final points = ((data['points'] as List?) ?? [])
        .cast<Map<String, dynamic>>()
        .map((p) => LatLng((p['lat'] as num).toDouble(), (p['lng'] as num).toDouble()))
        .toList();
    final visits = ((data['visits'] as List?) ?? []).cast<Map<String, dynamic>>();
    final attendance = ((data['attendance'] as List?) ?? []).cast<Map<String, dynamic>>();
    final plan = data['plan'] as Map<String, dynamic>?;
    final punches = attendance.map((a) => '${fmtTime(a['check_in'])} - ${fmtTime(a['check_out'])}').join(', ');
    final visitPoints = visits
        .where((v) => (v['lat'] as num? ?? 0) != 0)
        .map((v) => (v, LatLng((v['lat'] as num).toDouble(), (v['lng'] as num).toDouble())))
        .toList();
    final allPoints = [...points, ...visitPoints.map((e) => e.$2)];
    return [
      ListTile(
        dense: true,
        leading: const Icon(Icons.straighten),
        title: Text('${(data['distance_km'] as num? ?? 0).toStringAsFixed(1)} km · ${visits.length} visits'
            '${plan != null ? ' · beat ${plan['completed_count']}/${plan['planned_count']}' : ''}'),
        subtitle: Text(punches.isEmpty ? 'No punches' : 'Punches: $punches'),
      ),
      Expanded(
        child: allPoints.isEmpty
            ? const Center(child: Text('No location data for this day'))
            : AixoloMap(
                fitPoints: allPoints,
                center: allPoints.first,
                zoom: 14,
                children: [
                  PolylineLayer(polylines: travelPath(points)),
                  MarkerLayer(markers: [
                    if (points.isNotEmpty)
                      Marker(point: points.first, child: const Icon(Icons.trip_origin_rounded, color: AixoloColors.success)),
                    if (points.isNotEmpty)
                      Marker(
                        point: points.last,
                        width: MapPin.size.width,
                        height: MapPin.size.height,
                        alignment: Alignment.topCenter,
                        child: const MapPin(color: AixoloColors.danger, icon: Icons.navigation_rounded),
                      ),
                    for (final (visit, point) in visitPoints)
                      Marker(
                        point: point,
                        width: MapPinWithLabel.size.width,
                        height: MapPinWithLabel.size.height,
                        alignment: Alignment.topCenter,
                        child: MapPinWithLabel(
                          label: '${(visit['client'] as Map)['name']}',
                          color: visit['inside_geofence'] == false ? AixoloColors.warning : AixoloColors.purple,
                          icon: Icons.storefront_rounded,
                          onTap: () => showSnack(context,
                              '${(visit['client'] as Map)['name']} · ${fmtTime(visit['check_in_at'])}–${fmtTime(visit['check_out_at'])}'
                              '${visit['inside_geofence'] == false ? ' · outside geofence' : ''}'),
                        ),
                      ),
                  ]),
                ],
              ),
      ),
    ];
  }
}
