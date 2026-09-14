import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../core/format.dart';
import '../../core/services.dart';
import '../../core/theme.dart';
import '../../widgets/map.dart';
import 'timeline_screen.dart';

class TeamLiveScreen extends StatefulWidget {
  const TeamLiveScreen({super.key});

  @override
  State<TeamLiveScreen> createState() => _TeamLiveScreenState();
}

class _TeamLiveScreenState extends State<TeamLiveScreen> {
  Map<String, dynamic>? _data;
  String? _error;
  bool _loading = true;
  bool _showMap = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final data = await Services.api.get('/api/v1/team/live') as Map<String, dynamic>;
      setState(() {
        _data = data;
        _error = null;
      });
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<Map<String, dynamic>> get _members => ((_data?['members'] as List?) ?? []).cast<Map<String, dynamic>>();

  void _openTimeline(Map<String, dynamic> member) {
    final employee = member['employee'] as Map<String, dynamic>;
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => TimelineScreen(employeeId: employee['id'] as int, employeeName: employee['name'] as String),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('My Team'),
        actions: [
          IconButton(
            tooltip: _showMap ? 'List' : 'Map',
            icon: Icon(_showMap ? Icons.list : Icons.map),
            onPressed: () => setState(() => _showMap = !_showMap),
          ),
          IconButton(onPressed: _load, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: _loading && _data == null
          ? const Center(child: CircularProgressIndicator())
          : _error != null && _data == null
              ? Center(child: Text(_error!))
              : Column(
                  children: [
                    _Summary(summary: (_data!['summary'] as Map).cast<String, dynamic>()),
                    Expanded(child: _showMap ? _map() : _list()),
                  ],
                ),
    );
  }

  Widget _list() {
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        itemCount: _members.length,
        itemBuilder: (context, i) => _MemberTile(member: _members[i], onTap: () => _openTimeline(_members[i])),
      ),
    );
  }

  Widget _map() {
    final located = _members.where((m) => m['lat'] != null && m['punched_in'] == true).toList();
    if (located.isEmpty) return const Center(child: Text('Nobody is sharing location right now'));
    final points = located.map((m) => LatLng((m['lat'] as num).toDouble(), (m['lng'] as num).toDouble())).toList();
    return AppMap(
      fitPoints: points,
      center: points.first,
      children: [
        MarkerLayer(
          alignment: Alignment.topCenter,
          markers: [
            for (var i = 0; i < located.length; i++)
              Marker(
                point: points[i],
                width: MapPinWithLabel.size.width,
                height: MapPinWithLabel.size.height,
                alignment: Alignment.topCenter,
                child: MapPinWithLabel(
                  label: '${(located[i]['employee'] as Map)['name']}',
                  color: _alert(located[i]) ? AppColors.danger : AppColors.success,
                  initial: '${(located[i]['employee'] as Map)['name']}'.characters.firstOrNull?.toUpperCase(),
                  onTap: () => _openTimeline(located[i]),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

bool _alert(Map<String, dynamic> m) =>
    m['is_inactive'] == true || m['is_signal_lost'] == true || m['gps_on'] == false || m['is_low_battery'] == true;

class _Summary extends StatelessWidget {
  const _Summary({required this.summary});

  final Map<String, dynamic> summary;

  @override
  Widget build(BuildContext context) {
    Widget chip(String label, String key, Color color) => Chip(
          label: Text('$label ${summary[key] ?? 0}'),
          backgroundColor: color.withValues(alpha: 0.12),
        );
    return Padding(
      padding: const EdgeInsets.all(8),
      child: Wrap(spacing: 6, runSpacing: 6, children: [
        Chip(label: Text('In ${summary['punched_in'] ?? 0} / ${summary['total'] ?? 0}')),
        chip('Inactive', 'inactive', Colors.orange),
        chip('No signal', 'no_signal', Colors.red),
        chip('GPS off', 'gps_off', Colors.red),
        chip('Low battery', 'low_battery', Colors.amber),
      ]),
    );
  }
}

class _MemberTile extends StatelessWidget {
  const _MemberTile({required this.member, required this.onTap});

  final Map<String, dynamic> member;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final employee = member['employee'] as Map<String, dynamic>;
    final punchedIn = member['punched_in'] == true;
    final flags = <String>[
      if (member['is_inactive'] == true) 'Inactive',
      if (member['is_signal_lost'] == true) 'No signal',
      if (member['gps_on'] == false) 'GPS off',
      if (member['is_low_battery'] == true) 'Low battery',
    ];
    final color = !punchedIn ? Colors.grey : (flags.isEmpty ? Colors.green : Colors.red);
    final lines = <String>[
      punchedIn ? 'In since ${fmtTime(member['punched_in_at'])}' : 'Not punched in',
      if (member['at_client'] != null) 'At ${(member['at_client'] as Map)['name']}',
      if (member['battery'] != null) 'Battery ${member['battery']}%',
      if (member['last_ping_at'] != null) 'Seen ${fmtTime(member['last_ping_at'])}',
    ];
    return ListTile(
      leading: CircleAvatar(backgroundColor: color.withValues(alpha: 0.2), child: Icon(Icons.person, color: color)),
      title: Text(employee['name'] as String),
      subtitle: Text([lines.join(' · '), if (flags.isNotEmpty) flags.join(', ')].join('\n')),
      isThreeLine: flags.isNotEmpty,
      trailing: const Icon(Icons.timeline),
      onTap: onTap,
    );
  }
}
