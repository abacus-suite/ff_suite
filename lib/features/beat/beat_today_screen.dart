import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../core/geo.dart';
import '../../core/services.dart';
import '../../core/theme.dart';
import '../../widgets/common.dart';
import 'plan_day_screen.dart';
import '../clients/client_detail_screen.dart';
import '../clients/clients_screen.dart';

const _weekdayNames = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];

/// The day's journey plan: one or several routes, each customer with its plan status.
class BeatTodayScreen extends StatefulWidget {
  const BeatTodayScreen({super.key, this.embedded = false});

  final bool embedded;

  @override
  State<BeatTodayScreen> createState() => _BeatTodayScreenState();
}

class _BeatTodayScreenState extends State<BeatTodayScreen> {
  DateTime _day = DateTime.now();
  Map<String, dynamic>? _data;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    Services.refresh.addListener(_load);
    _load();
  }

  @override
  void dispose() {
    Services.refresh.removeListener(_load);
    super.dispose();
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() => _loading = true);
    try {
      final pos = await lastKnownPosition();
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

  Future<void> _adhoc() async {
    final client = await Navigator.of(context)
        .push<Map<String, dynamic>>(MaterialPageRoute(builder: (_) => const ClientsScreen(pickMode: true)));
    if (client != null) await _openClient(client['id'] as int);
  }

  @override
  Widget build(BuildContext context) {
    final label = Services.auth.profile!.routeLabel;
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: !widget.embedded,
        title: Text('My $label Plan'),
        actions: [
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
        icon: const Icon(Icons.add_location_alt_rounded),
        label: const Text('Adhoc visit'),
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
                        style: const TextStyle(color: AixoloColors.muted, fontSize: 12)),
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
    final clients = ((data['clients'] as List?) ?? []).cast<Map<String, dynamic>>();
    final adhoc = ((data['adhoc_visits'] as List?) ?? []).cast<Map<String, dynamic>>();
    return [
      if (plans.isEmpty)
        EmptyView(icon: Icons.event_busy_rounded,
            text: 'No $label planned for this day.\nUse "Adhoc visit" to visit anyone.'),
      for (final plan in plans) _planCard(plan),
      if (clients.isNotEmpty) ...[
        const Padding(
          padding: EdgeInsets.fromLTRB(4, 14, 4, 4),
          child: Text('Customers', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
        ),
        for (final client in clients) _clientTile(client, showRoute: plans.length > 1),
      ],
      if (adhoc.isNotEmpty) ...[
        const Padding(
          padding: EdgeInsets.fromLTRB(4, 14, 4, 4),
          child: Text('Adhoc visits', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
        ),
        for (final visit in adhoc)
          Card(
            child: ListTile(
              leading: const CircleAvatar(backgroundColor: Color(0xFFEDE8FF), child: Icon(Icons.bolt_rounded, color: AixoloColors.purple)),
              title: Text('${(visit['client'] as Map)['name']}'),
              subtitle: Text('${fmtTime(visit['check_in_at'])}–${fmtTime(visit['check_out_at'])}'),
              trailing: StatusBadge(visit['state'] == 'ongoing' ? 'ongoing' : 'visited'),
              onTap: () => _openClient((visit['client'] as Map)['id'] as int),
            ),
          ),
      ],
    ];
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
                backgroundColor: AixoloColors.border,
                valueColor: const AlwaysStoppedAnimation(AixoloColors.teal),
              ),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 14,
              runSpacing: 6,
              children: [
                count(Icons.flag_rounded, AixoloColors.primary, '${plan['planned_count']} planned'),
                count(Icons.check_circle_rounded, AixoloColors.success, '${plan['completed_count']} visited'),
                if ((plan['missed_count'] as num? ?? 0) > 0)
                  count(Icons.cancel_rounded, AixoloColors.danger, '${plan['missed_count']} missed'),
                if ((plan['adhoc_count'] as num? ?? 0) > 0)
                  count(Icons.bolt_rounded, AixoloColors.purple, '${plan['adhoc_count']} adhoc'),
                count(Icons.route_rounded, AixoloColors.muted, '${plan['actual_km']} km'),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _clientTile(Map<String, dynamic> client, {required bool showRoute}) {
    final visitStatus = client['visit_status'] as String?;
    final status = visitStatus == 'ongoing' ? 'ongoing' : (client['plan_status'] as String? ?? 'planned');
    final color = switch (status) {
      'visited' => AixoloColors.success,
      'missed' => AixoloColors.danger,
      'cancelled' => AixoloColors.warning,
      'ongoing' => AixoloColors.sky,
      _ => AixoloColors.primary,
    };
    final details = [
      if (showRoute) asText((client['route'] as Map?)?['name']),
      asText(client['address']),
      if (client['distance_m'] != null) fmtDistance(client['distance_m'] as num?),
    ].whereType<String>().join(' · ');
    return Card(
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: color.withValues(alpha: 0.14),
          child: Text('${client['sequence']}', style: TextStyle(color: color, fontWeight: FontWeight.w800)),
        ),
        title: Text('${client['name']}', style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(details.isEmpty ? lastVisitLabel(client) : details, maxLines: 2, overflow: TextOverflow.ellipsis),
        trailing: StatusBadge(status),
        onTap: () => _openClient(client['id'] as int),
      ),
    );
  }
}
