import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../core/api_client.dart';
import '../../core/format.dart';
import '../../core/services.dart';
import '../../core/theme.dart';
import '../../widgets/common.dart';
import '../../widgets/map.dart';
import '../../widgets/skeleton.dart';
import 'timeline_screen.dart';

/// Where the team is right now: who is working, who needs a look, and each person to open.
class TeamLiveScreen extends StatefulWidget {
  const TeamLiveScreen({super.key, this.startOnMap = false});

  /// Home's "Live map" opens straight on the map; My Team / Reports open on the list.
  final bool startOnMap;

  @override
  State<TeamLiveScreen> createState() => _TeamLiveScreenState();
}

class _TeamLiveScreenState extends State<TeamLiveScreen> {
  Map<String, dynamic>? _data;
  String? _error;
  bool _loading = true;
  late bool _showMap = widget.startOnMap;
  String _filter = 'all';
  String _find = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final data = await Services.api.get('/api/v1/team/live') as Map<String, dynamic>;
      if (mounted) {
        setState(() {
          _data = data;
          _error = null;
        });
      }
    } catch (e) {
      final text = e is ApiException && e.status == 404 ? 'The live map is not switched on yet on the server.' : e.toString();
      if (mounted) setState(() => _error = text);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  static String _nameOf(Map<String, dynamic> m) {
    final e = m['employee'];
    return '${e is Map ? e['name'] : (m['employee_name'] ?? m['name'] ?? '')}';
  }

  static double? _num(dynamic v) => v is num ? v.toDouble() : double.tryParse('${v ?? ''}');

  /// Where a person was last seen: `lat`/`lng` on the row, or inside `location` / `last_location`.
  static LatLng? _pointOf(Map<String, dynamic> m) {
    for (final src in [m, m['location'], m['last_location'], m['last_ping']]) {
      if (src is! Map) continue;
      final lat = _num(src['lat'] ?? src['latitude']);
      final lng = _num(src['lng'] ?? src['lon'] ?? src['longitude']);
      if (lat != null && lng != null && !(lat == 0 && lng == 0)) return LatLng(lat, lng);
    }
    return null;
  }

  List<Map<String, dynamic>> get _members => ((_data?['members'] as List?) ?? []).cast<Map<String, dynamic>>();
  Map<String, dynamic> get _summary => (_data?['summary'] as Map?)?.cast<String, dynamic>() ?? {};

  bool _alert(Map<String, dynamic> m) =>
      m['punched_in'] == true && (m['is_inactive'] == true || m['is_signal_lost'] == true || m['gps_on'] == false || m['is_low_battery'] == true);

  List<Map<String, dynamic>> get _shown {
    final needle = _find.trim().toLowerCase();
    return _members.where((m) {
      final ok = switch (_filter) {
        'working' => m['punched_in'] == true,
        'out' => m['punched_in'] != true,
        'alerts' => _alert(m),
        'client' => m['at_client'] != null,
        _ => true,
      };
      if (!ok) return false;
      return needle.isEmpty || _nameOf(m).toLowerCase().contains(needle);
    }).toList();
  }

  void _open(Map<String, dynamic> member) {
    final e = member['employee'];
    final id = e is Map ? e['id'] as int? : member['employee_id'] as int?;
    if (id == null) return;
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => TimelineScreen(employeeId: id, employeeName: _nameOf(member)),
    ));
  }

  Widget _hero() {
    final s = _summary;
    final total = (s['total'] as num?) ?? 0;
    final inNow = (s['punched_in'] as num?) ?? 0;
    final alerts = _members.where(_alert).length;
    Widget tile(String value, String label, IconData icon) => Expanded(
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 3),
            padding: const EdgeInsets.symmetric(vertical: 11),
            decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(16)),
            child: Column(children: [
              Icon(icon, color: Colors.white, size: 17),
              const SizedBox(height: 4),
              Text(value, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 18)),
              Text(label, style: const TextStyle(color: Colors.white, fontSize: 10.5)),
            ]),
          ),
        );
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [Color(0xFF065F46), Color(0xFF10B981), Color(0xFF06B6D4)], begin: Alignment.topLeft, end: Alignment.bottomRight),
        borderRadius: BorderRadius.circular(26),
        boxShadow: [BoxShadow(color: const Color(0xFF10B981).withValues(alpha: 0.28), blurRadius: 20, offset: const Offset(0, 9))],
      ),
      child: Column(children: [
        Row(children: [
          const Icon(Icons.sensors_rounded, color: Colors.white),
          const SizedBox(width: 8),
          const Text('Live now', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 17)),
          const Spacer(),
          Text(fmtTime(_data?['server_time']), style: const TextStyle(color: Colors.white, fontSize: 12)),
        ]),
        const SizedBox(height: 12),
        Row(children: [
          tile('$inNow/$total', 'Working', Icons.directions_walk_rounded),
          tile('${s['at_client'] ?? 0}', 'At a customer', Icons.storefront_rounded),
          tile('$alerts', 'Need a look', Icons.warning_amber_rounded),
        ]),
      ]),
    );
  }

  Widget _filters() {
    final s = _summary;
    final items = <(String, String)>[
      ('all', 'All ${_members.length}'),
      ('working', 'Working ${s['punched_in'] ?? 0}'),
      ('client', 'At customer ${s['at_client'] ?? 0}'),
      ('alerts', 'Alerts ${_members.where(_alert).length}'),
      ('out', 'Not in ${_members.where((m) => m['punched_in'] != true).length}'),
    ];
    return SizedBox(
      height: 40,
      child: ListView(scrollDirection: Axis.horizontal, children: [
        for (final (key, label) in items)
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(label: Text(label), selected: _filter == key, onSelected: (_) => setState(() => _filter = key)),
          ),
      ]),
    );
  }

  Widget _card(Map<String, dynamic> m) {
    final e = {'name': _nameOf(m)};
    final punchedIn = m['punched_in'] == true;
    final flags = <(IconData, String)>[
      if (m['is_inactive'] == true) (Icons.hourglass_bottom_rounded, 'Not moving'),
      if (m['is_signal_lost'] == true) (Icons.signal_wifi_off_rounded, 'No signal'),
      if (m['gps_on'] == false) (Icons.location_off_rounded, 'GPS off'),
      if (m['is_low_battery'] == true) (Icons.battery_alert_rounded, 'Low battery'),
    ];
    final colour = !punchedIn ? AppColors.muted : (flags.isEmpty ? AppColors.success : AppColors.danger);
    final battery = m['battery'] as num?;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: const Color(0xFF1B3A7A).withValues(alpha: 0.06), blurRadius: 12, offset: const Offset(0, 4))],
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _open(m),
        child: IntrinsicHeight(
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Container(width: 6, color: colour),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    CircleAvatar(
                      radius: 21,
                      backgroundColor: colour.withValues(alpha: 0.14),
                      child: Text('${e['name']}'.isEmpty ? '?' : '${e['name']}'[0].toUpperCase(),
                          style: TextStyle(fontWeight: FontWeight.w900, color: colour, fontSize: 18)),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('${e['name']}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15)),
                        Text(
                            punchedIn ? 'Working since ${fmtTime(m['punched_in_at'])}' : 'Not checked in',
                            style: TextStyle(fontSize: 12.5, color: punchedIn ? AppColors.success : AppColors.muted, fontWeight: FontWeight.w600)),
                      ]),
                    ),
                    if (battery != null)
                      Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(battery <= 20 ? Icons.battery_alert_rounded : Icons.battery_full_rounded, size: 17, color: battery <= 20 ? AppColors.danger : AppColors.muted),
                        const SizedBox(width: 2),
                        Text('$battery%', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                      ]),
                    const Icon(Icons.chevron_right_rounded, color: AppColors.muted),
                  ]),
                  if (m['at_client'] != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Row(children: [
                        const Icon(Icons.storefront_rounded, size: 15, color: AppColors.purple),
                        const SizedBox(width: 5),
                        Expanded(child: Text('At ${(m['at_client'] as Map)['name']}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700))),
                      ]),
                    ),
                  if (m['last_ping_at'] != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text('Last seen ${fmtTime(m['last_ping_at'])}', style: const TextStyle(fontSize: 11.5, color: AppColors.muted)),
                    ),
                  if (flags.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Wrap(spacing: 6, runSpacing: 4, children: [
                        for (final (icon, label) in flags)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(color: AppColors.danger.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12)),
                            child: Row(mainAxisSize: MainAxisSize.min, children: [
                              Icon(icon, size: 13, color: AppColors.danger),
                              const SizedBox(width: 4),
                              Text(label, style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: AppColors.danger)),
                            ]),
                          ),
                      ]),
                    ),
                ]),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _list() {
    final rows = _shown;
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 40),
        children: [
          _hero(),
          const SizedBox(height: 12),
          TextField(
            onChanged: (v) => setState(() => _find = v),
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search_rounded),
              hintText: 'Find a person',
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: BorderSide.none),
              isDense: true,
            ),
          ),
          const SizedBox(height: 10),
          _filters(),
          const SizedBox(height: 10),
          if (rows.isEmpty) const Padding(padding: EdgeInsets.all(30), child: Center(child: Text('Nobody matches.', style: TextStyle(color: AppColors.muted)))),
          for (final m in rows) _card(m),
        ],
      ),
    );
  }

  /// "Last seen 19 Oct, 2:51 pm" for a grey pin's note.
  static String _lastSeen(Map<String, dynamic> m) {
    final at = DateTime.tryParse('${m['last_ping_at'] ?? ''}')?.toLocal();
    if (at == null) return '';
    final now = DateTime.now();
    final sameDay = at.year == now.year && at.month == now.month && at.day == now.day;
    return sameDay ? fmtTime(m['last_ping_at']) : '${at.day} ${monthNames[at.month - 1].substring(0, 3)}';
  }

  /// Everyone with a known place: checked-in people in green (red when something needs a look),
  /// and the others in grey where they were last seen, so the map is never just empty.
  Widget _map() {
    final located = _shown.where((m) => _pointOf(m) != null).toList()
      // Grey pins first, so the live ones are drawn on top.
      ..sort((a, b) => (a['punched_in'] == true ? 1 : 0).compareTo(b['punched_in'] == true ? 1 : 0));
    if (located.isEmpty) {
      return const Center(
          child: Padding(
              padding: EdgeInsets.all(30),
              child: Text('Nobody in your team has shared a location yet.', textAlign: TextAlign.center, style: TextStyle(color: AppColors.muted))));
    }
    final live = located.where((m) => m['punched_in'] == true).toList();
    // Fit the map to the people working now; with nobody working, to everyone's last place.
    final fit = (live.isEmpty ? located : live).map((m) => _pointOf(m)!).toList();
    return Stack(children: [
      AppMap(
        fitPoints: fit,
        center: fit.first,
        children: [
          MarkerLayer(
            alignment: Alignment.topCenter,
            markers: [
              for (final m in located)
                Marker(
                  point: _pointOf(m)!,
                  width: MapPinWithLabel.size.width,
                  height: MapPinWithLabel.size.height,
                  alignment: Alignment.topCenter,
                  child: MapPinWithLabel(
                    label: m['punched_in'] == true || _lastSeen(m).isEmpty ? _nameOf(m) : '${_nameOf(m)} · ${_lastSeen(m)}',
                    color: m['punched_in'] != true ? AppColors.muted : (_alert(m) ? AppColors.danger : AppColors.success),
                    initial: _nameOf(m).characters.firstOrNull?.toUpperCase(),
                    onTap: () => _open(m),
                  ),
                ),
            ],
          ),
        ],
      ),
      Positioned(
        left: 12,
        right: 12,
        top: 10,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.95),
            borderRadius: BorderRadius.circular(14),
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 8)],
          ),
          child: Text(
            live.isEmpty
                ? 'Nobody is checked in now. Grey pins show where each person was last seen.'
                : '${live.length} working now · grey pins: not checked in, last place seen',
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
          ),
        ),
      ),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(_showMap ? 'Live map' : 'My Team'),
        actions: [
          IconButton(onPressed: _load, icon: const Icon(Icons.refresh_rounded)),
        ],
      ),
      body: _loading && _data == null
          ? const LoadingView()
          : _error != null && _data == null
              ? ErrorView(message: _error!, onRetry: _load)
              : Column(children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                    child: SizedBox(
                      width: double.infinity,
                      child: SegmentedButton<bool>(
                        showSelectedIcon: false,
                        segments: const [
                          ButtonSegment(value: false, label: Text('List'), icon: Icon(Icons.view_agenda_rounded)),
                          ButtonSegment(value: true, label: Text('Map'), icon: Icon(Icons.map_rounded)),
                        ],
                        selected: {_showMap},
                        onSelectionChanged: (v) => setState(() => _showMap = v.first),
                      ),
                    ),
                  ),
                  Expanded(child: _showMap ? _map() : _list()),
                ]),
    );
  }
}
