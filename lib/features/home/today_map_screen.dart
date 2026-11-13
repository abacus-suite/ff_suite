import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../core/format.dart';
import '../../core/geo.dart';
import '../../core/services.dart';
import '../../core/theme.dart';
import '../../widgets/common.dart';
import '../../widgets/map.dart';
import '../beat/added_visits.dart';
import '../clients/client_detail_screen.dart';

/// Where the person is, the outlets of today's beat plan and the other outlets, each in its own colour.
class TodayMapScreen extends StatefulWidget {
  const TodayMapScreen({super.key, required this.planned});

  /// Today's planned customers, as the Home card has them.
  final List<Map<String, dynamic>> planned;

  @override
  State<TodayMapScreen> createState() => _TodayMapScreenState();
}

class _TodayMapScreenState extends State<TodayMapScreen> {
  // Me: blue. Planned and still to visit: orange. Planned and visited: green. Any other outlet: purple.
  static const _meColour = AppColors.sky;
  static const _plannedColour = AppColors.warning;
  static const _doneColour = AppColors.success;
  static const _otherColour = AppColors.purple;

  LatLng? _me;
  List<Map<String, dynamic>> _others = [];
  bool _loading = true;
  String? _error;
  bool _showOthers = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  LatLng? _point(Map<String, dynamic> c) {
    final lat = c['lat'] ?? c['latitude'];
    final lng = c['lng'] ?? c['longitude'];
    if (lat is! num || lng is! num || (lat == 0 && lng == 0)) return null;
    return LatLng(lat.toDouble(), lng.toDouble());
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      try {
        final pos = await currentPosition(recentOk: true);
        _me = LatLng(pos.latitude, pos.longitude);
      } catch (_) {
        // No fix: the map still shows the outlets.
      }
      final found = await Services.api.get('/api/v1/clients', query: {'limit': 500});
      final list = found is Map ? (found['clients'] as List? ?? []) : (found as List? ?? []);
      final plannedIds = {for (final c in widget.planned) c['id']};
      _others = [
        for (final c in list.cast<Map<String, dynamic>>())
          if (!plannedIds.contains(c['id']) && _point(c) != null) c,
      ];
    } catch (e) {
      _error = e.toString();
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  bool _done(Map<String, dynamic> c) => c['visit_status'] == 'done' || c['plan_status'] == 'visited';

  void _open(Map<String, dynamic> c, String kind) {
    final here = _me;
    final p = _point(c);
    final km = here != null && p != null ? const Distance().as(LengthUnit.Kilometer, here, p) : null;
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheet) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${c['name']}', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
            const SizedBox(height: 2),
            Text([kind, if (km != null) '${km.toStringAsFixed(1)} km away'].join(' · '),
                style: const TextStyle(color: AppColors.muted, fontSize: 12.5)),
            if ('${c['address'] ?? ''}'.trim().isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text('${c['address']}', style: const TextStyle(fontSize: 13)),
              ),
            const SizedBox(height: 12),
            FilledButton(
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(46)),
              onPressed: () async {
                Navigator.pop(sheet);
                if (kind == 'Other outlet') {
                  // Not in today's beat: it joins it as an added visit, as with "Add a Visit".
                  await AddedVisits.add([c]);
                  if (mounted) showSnack(context, '${c['name']} added to the beat of the day');
                  return;
                }
                Navigator.of(context).push(MaterialPageRoute(builder: (_) => ClientDetailScreen(clientId: c['id'] as int)));
              },
              child: Text(kind == 'Other outlet' ? 'Add a Visit' : 'Open'),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _legend(Color colour, String text, {bool dot = false}) => Row(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: dot ? 12 : 11,
          height: dot ? 12 : 11,
          decoration: BoxDecoration(color: colour, shape: dot ? BoxShape.circle : BoxShape.rectangle, borderRadius: dot ? null : BorderRadius.circular(3)),
        ),
        const SizedBox(width: 5),
        Text(text, style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700)),
      ]);

  @override
  Widget build(BuildContext context) {
    final planned = [for (final c in widget.planned) if (_point(c) != null) c];
    final others = _showOthers ? _others : const <Map<String, dynamic>>[];
    final all = <LatLng>[
      if (_me != null) _me!,
      for (final c in planned) _point(c)!,
      if (planned.isEmpty) for (final c in others.take(30)) _point(c)!,
    ];
    return Scaffold(
      appBar: AppBar(
        title: const Text("Today's Map", style: TextStyle(fontWeight: FontWeight.w900, fontSize: 20)),
        actions: [
          IconButton(
            tooltip: _showOthers ? 'Hide other outlets' : 'Show other outlets',
            icon: Icon(_showOthers ? Icons.visibility_rounded : Icons.visibility_off_rounded),
            onPressed: () => setState(() => _showOthers = !_showOthers),
          ),
        ],
      ),
      body: _error != null
          ? ErrorView(message: _error!, onRetry: _load)
          : Stack(children: [
              AppMap(
                center: all.isNotEmpty ? all.first : null,
                zoom: 12,
                myLocation: _me,
                fitPoints: all,
                children: [
                  MarkerLayer(
                    alignment: Alignment.topCenter,
                    markers: [
                      for (final c in others)
                        Marker(
                          point: _point(c)!,
                          width: MapPin.size.width,
                          height: MapPin.size.height,
                          alignment: Alignment.topCenter,
                          child: GestureDetector(
                              onTap: () => _open(c, 'Other outlet'),
                              child: const MapPin(color: _otherColour, icon: Icons.storefront_rounded)),
                        ),
                      for (final (i, c) in planned.indexed)
                        Marker(
                          point: _point(c)!,
                          width: MapPin.size.width,
                          height: MapPin.size.height,
                          alignment: Alignment.topCenter,
                          child: GestureDetector(
                              onTap: () => _open(c, _done(c) ? 'Planned · visited' : 'Planned today'),
                              child: MapPin(color: _done(c) ? _doneColour : _plannedColour, initial: '${i + 1}')),
                        ),
                    ],
                  ),
                  MarkerLayer(
                    markers: [
                      if (_me != null)
                        Marker(
                            point: _me!,
                            width: MyLocationDot.size,
                            height: MyLocationDot.size,
                            child: const MyLocationDot(color: _meColour)),
                    ],
                  ),
                ],
              ),
              // What each colour is.
              Positioned(
                left: 12,
                right: 12,
                top: 10,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.94),
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: const [BoxShadow(color: Color(0x22000000), blurRadius: 8, offset: Offset(0, 2))],
                  ),
                  child: Wrap(spacing: 12, runSpacing: 4, children: [
                    _legend(_meColour, 'You', dot: true),
                    _legend(_plannedColour, 'Planned (${planned.where((c) => !_done(c)).length})'),
                    _legend(_doneColour, 'Visited (${planned.where(_done).length})'),
                    _legend(_otherColour, 'Other outlets (${_others.length})'),
                  ]),
                ),
              ),
              if (_loading) const Positioned(top: 70, left: 0, right: 0, child: Center(child: CircularProgressIndicator(strokeWidth: 2.5))),
              if (!_loading && planned.isEmpty && _others.isEmpty)
                const Center(child: EmptyView(icon: Icons.map_rounded, text: 'No outlet locations to show')),
            ]),
    );
  }
}
