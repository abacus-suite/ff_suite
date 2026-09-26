import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../core/format.dart';
import '../../core/services.dart';
import '../../core/theme.dart';
import '../../widgets/common.dart';
import '../../widgets/map.dart';
import '../clients/client_detail_screen.dart';

/// My day from the first punch to now: what happened and where, as a list you
/// can read and a map you can look at.
class DayJourneyScreen extends StatefulWidget {
  const DayJourneyScreen({super.key, this.showMapFirst = false});

  /// Opens straight on the map, for the expand button on the travel card.
  final bool showMapFirst;

  @override
  State<DayJourneyScreen> createState() => _DayJourneyScreenState();
}

class _DayJourneyScreenState extends State<DayJourneyScreen> with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 2, vsync: this, initialIndex: widget.showMapFirst ? 1 : 0);
  DateTime _day = DateUtils.dateOnly(DateTime.now());
  Map<String, dynamic>? _data;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data =
          await Services.api.get('/api/v1/me/timeline', query: {'date': fmtDate(_day)}) as Map<String, dynamic>;
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

  List<Map<String, dynamic>> get _points =>
      ((_data?['points'] as List?) ?? []).cast<Map<String, dynamic>>();

  List<LatLng> get _path => _points
      .map((p) => LatLng((p['lat'] as num).toDouble(), (p['lng'] as num).toDouble()))
      .toList();

  List<Map<String, dynamic>> get _visits => ((_data?['visits'] as List?) ?? []).cast<Map<String, dynamic>>();

  List<Map<String, dynamic>> get _attendance =>
      ((_data?['attendance'] as List?) ?? []).cast<Map<String, dynamic>>();

  num get _km => (_data?['distance_km'] as num?) ?? 0;

  bool get _isToday => fmtDate(_day) == fmtDate(DateTime.now());

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('My day'),
        bottom: TabBar(
          controller: _tabs,
          tabs: const [
            Tab(icon: Icon(Icons.timeline_rounded), text: 'Timeline'),
            Tab(icon: Icon(Icons.map_rounded), text: 'Map'),
          ],
        ),
      ),
      body: Column(
        children: [
          _dayBar(),
          if (_loading) const LinearProgressIndicator(minHeight: 2),
          Expanded(
            child: _error != null && _data == null
                ? ErrorView(message: _error!, onRetry: _load)
                : TabBarView(
                    controller: _tabs,
                    children: [_timeline(), _map()],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _dayBar() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        children: [
          IconButton(onPressed: () => _shift(-1), icon: const Icon(Icons.chevron_left_rounded)),
          Expanded(
            child: Center(
              child: Text(_isToday ? 'Today' : fmtDate(_day),
                  style: const TextStyle(fontWeight: FontWeight.w800)),
            ),
          ),
          IconButton(
              onPressed: _isToday ? null : () => _shift(1), icon: const Icon(Icons.chevron_right_rounded)),
        ],
      ),
    );
  }

  /// Punches, visits and the travel between them, in the order they happened.
  List<_Moment> _moments() {
    final moments = <_Moment>[];
    for (final punch in _attendance) {
      final inAt = DateTime.tryParse('${punch['check_in']}')?.toLocal();
      if (inAt != null) {
        moments.add(_Moment(
          at: inAt,
          icon: Icons.login_rounded,
          colour: AppColors.success,
          title: 'Checked in',
          detail: asText(punch['in_address']) ?? 'Day started',
        ));
      }
      final outAt = DateTime.tryParse('${punch['check_out']}')?.toLocal();
      if (outAt != null) {
        moments.add(_Moment(
          at: outAt,
          icon: Icons.logout_rounded,
          colour: AppColors.danger,
          title: 'Checked out',
          detail: asText(punch['out_address']) ?? 'Day ended',
        ));
      }
    }
    for (final visit in _visits) {
      final inAt = DateTime.tryParse('${visit['check_in_at']}')?.toLocal();
      if (inAt == null) continue;
      final outAt = DateTime.tryParse('${visit['check_out_at']}')?.toLocal();
      final client = (visit['client'] as Map?)?.cast<String, dynamic>();
      moments.add(_Moment(
        at: inAt,
        icon: Icons.storefront_rounded,
        colour: visit['inside_geofence'] == false ? AppColors.warning : AppColors.purple,
        title: '${client?['name'] ?? 'Visit'}',
        detail: [
          outAt == null ? 'In progress' : 'Until ${fmtTime(visit['check_out_at'])}',
          if (visit['inside_geofence'] == false) 'Outside the customer area',
          if (asText(visit['outcome']) != null) '${visit['outcome']}',
        ].join(' · '),
        clientId: client?['id'] as int?,
      ));
    }
    moments.sort((a, b) => a.at.compareTo(b.at));
    return moments;
  }

  /// How far the person moved between two times, from the day's positions.
  double _kmBetween(DateTime from, DateTime to) {
    var total = 0.0;
    LatLng? previous;
    for (final point in _points) {
      final at = DateTime.tryParse('${point['ts']}')?.toLocal();
      if (at == null || at.isBefore(from) || at.isAfter(to)) continue;
      final here = LatLng((point['lat'] as num).toDouble(), (point['lng'] as num).toDouble());
      if (previous != null) total += const Distance().as(LengthUnit.Kilometer, previous, here);
      previous = here;
    }
    return total;
  }

  Widget _timeline() {
    final moments = _moments();
    if (moments.isEmpty && !_loading) {
      return const EmptyView(icon: Icons.timeline_rounded, text: 'Nothing recorded for this day yet');
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
        children: [
          _summary(moments),
          const SizedBox(height: 12),
          for (final (i, moment) in moments.indexed) ...[
            if (i > 0) _travelBetween(moments[i - 1].at, moment.at),
            _momentTile(moment, first: i == 0, last: i == moments.length - 1),
          ],
          if (moments.isNotEmpty && _isToday) _travelBetween(moments.last.at, DateTime.now(), toNow: true),
        ],
      ),
    );
  }

  Widget _summary(List<_Moment> moments) {
    final first = moments.isEmpty ? null : moments.first.at;
    final last = _isToday ? DateTime.now() : (moments.isEmpty ? null : moments.last.at);
    final minutes = first != null && last != null ? last.difference(first).inMinutes : 0;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            _figure('${_km.toStringAsFixed(1)} km', 'Travelled', Icons.route_rounded, AppColors.primary),
            _figure('${_visits.length}', 'Visits', Icons.storefront_rounded, AppColors.purple),
            _figure(minutes <= 0 ? '-' : (minutes >= 60 ? '${minutes ~/ 60}h ${minutes % 60}m' : '$minutes min'),
                'On the road', Icons.timer_rounded, AppColors.success),
          ],
        ),
      ),
    );
  }

  Widget _figure(String value, String label, IconData icon, Color tint) => Expanded(
        child: Column(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(color: tint.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(11)),
              child: Icon(icon, size: 18, color: tint),
            ),
            const SizedBox(height: 6),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(value, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15)),
            ),
            Text(label, style: const TextStyle(fontSize: 11, color: AppColors.muted)),
          ],
        ),
      );

  /// The dotted stretch between two moments, with the distance on it.
  Widget _travelBetween(DateTime from, DateTime to, {bool toNow = false}) {
    final km = _kmBetween(from, to);
    final minutes = to.difference(from).inMinutes;
    if (km < 0.05 && minutes < 5) return const SizedBox(height: 6);
    return Padding(
      padding: const EdgeInsets.only(left: 17),
      child: Row(
        children: [
          Container(width: 2, height: 34, color: AppColors.border),
          const SizedBox(width: 18),
          Icon(toNow ? Icons.more_horiz_rounded : Icons.directions_walk_rounded,
              size: 15, color: AppColors.muted),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              [
                if (km >= 0.05) '${km.toStringAsFixed(1)} km',
                if (minutes > 0) minutes >= 60 ? '${minutes ~/ 60}h ${minutes % 60}m' : '$minutes min',
                if (toNow) 'so far',
              ].join(' · '),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12, color: AppColors.muted),
            ),
          ),
        ],
      ),
    );
  }

  Widget _momentTile(_Moment moment, {required bool first, required bool last}) {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: moment.clientId == null
          ? null
          : () => Navigator.of(context)
              .push(MaterialPageRoute(builder: (_) => ClientDetailScreen(clientId: moment.clientId!))),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: moment.colour.withValues(alpha: 0.13),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(moment.icon, size: 18, color: moment.colour),
              ),
            ],
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Container(
              margin: const EdgeInsets.only(bottom: 2),
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(moment.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
                      ),
                      Text(_clock(moment.at),
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.muted)),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(moment.detail,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12, color: AppColors.muted)),
                ],
              ),
            ),
          ),
          if (moment.clientId != null) const Icon(Icons.chevron_right_rounded, color: AppColors.muted),
        ],
      ),
    );
  }

  String _clock(DateTime at) {
    final hour = at.hour % 12 == 0 ? 12 : at.hour % 12;
    return '${hour.toString().padLeft(2, '0')}:${at.minute.toString().padLeft(2, '0')} '
        '${at.hour < 12 ? 'AM' : 'PM'}';
  }

  Widget _map() {
    final path = _path;
    final visitPoints = _visits
        .where((v) => (v['lat'] as num? ?? 0) != 0)
        .map((v) => (v, LatLng((v['lat'] as num).toDouble(), (v['lng'] as num).toDouble())))
        .toList();
    final all = [...path, ...visitPoints.map((e) => e.$2)];
    if (all.isEmpty) {
      return const EmptyView(icon: Icons.map_rounded, text: 'No positions recorded for this day');
    }
    return AppMap(
      fitPoints: all,
      center: all.first,
      zoom: 14,
      children: [
        PolylineLayer(polylines: travelPath(path)),
        MarkerLayer(markers: [
          if (path.isNotEmpty)
            Marker(point: path.first, child: const Icon(Icons.trip_origin_rounded, color: AppColors.success)),
          if (path.isNotEmpty)
            Marker(
              point: path.last,
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
                onTap: () => showSnack(context,
                    '${(visit['client'] as Map)['name']} · ${fmtTime(visit['check_in_at'])}'
                    '${visit['check_out_at'] != null ? '–${fmtTime(visit['check_out_at'])}' : ''}'),
              ),
            ),
        ]),
      ],
    );
  }
}

/// One thing that happened today.
class _Moment {
  _Moment({
    required this.at,
    required this.icon,
    required this.colour,
    required this.title,
    required this.detail,
    this.clientId,
  });

  final DateTime at;
  final IconData icon;
  final Color colour;
  final String title;
  final String detail;
  final int? clientId;
}
