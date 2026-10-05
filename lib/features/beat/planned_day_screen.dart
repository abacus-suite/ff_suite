import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../core/services.dart';
import '../../core/theme.dart';
import '../../widgets/common.dart';
import '../clients/client_detail_screen.dart';
import 'plan_beat_screen.dart';
import '../../widgets/skeleton.dart';

/// One planned day: who is on it, how each call went, and who was called on
/// without being planned.
///
/// The day is the unit of work, so everything about it is on one screen rather
/// than split across a route card per beat. The unplanned visits sit at the
/// bottom because that is the honest shape of a day - the plan, then what
/// actually happened as well.
class PlannedDayScreen extends StatefulWidget {
  const PlannedDayScreen({
    super.key,
    required this.date,
    this.member = 'me',
    this.memberName,
  });

  final DateTime date;
  final String member;
  final String? memberName;

  @override
  State<PlannedDayScreen> createState() => _PlannedDayScreenState();
}

class _PlannedDayScreenState extends State<PlannedDayScreen> {
  Map<String, dynamic>? _day;
  bool _loading = true;
  String? _error;
  String _filter = 'all';

  List<Map<String, dynamic>> get _clients =>
      ((_day?['clients'] as List?) ?? []).cast<Map<String, dynamic>>();

  List<Map<String, dynamic>> get _adhoc =>
      ((_day?['adhoc_visits'] as List?) ?? []).cast<Map<String, dynamic>>();

  int _count(String status) => _clients.where((c) => c['visit_status'] == status).length;

  bool get _past => DateUtils.dateOnly(widget.date).isBefore(DateUtils.dateOnly(DateTime.now()));

  /// Planned for a day that has gone and never called on.
  int get _missedCount => _past ? _count('pending') : 0;

  List<Map<String, dynamic>> get _shown {
    if (_filter == 'all') return _clients;
    if (_filter == 'missed') return _clients.where((c) => c['visit_status'] == 'pending').toList();
    if (_filter == 'pending' && _past) return const [];
    return _clients.where((c) => c['visit_status'] == _filter).toList();
  }

  bool get _isMine => widget.member == 'me' || widget.member.isEmpty;

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
      final data = await Services.api.get('/api/v1/beat/today', query: {
        'date': fmtDate(widget.date),
        if (!_isMine) 'member': widget.member,
      }) as Map<String, dynamic>;
      if (mounted) setState(() => _day = data);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _addCustomers() async {
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => PlanBeatScreen(
        date: widget.date,
        member: widget.member,
        memberName: widget.memberName,
        startOnCustomers: true,
      ),
    ));
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final past = DateUtils.dateOnly(widget.date).isBefore(DateUtils.dateOnly(DateTime.now()));
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(fmtDate(widget.date)),
        // Somebody else's day is somebody else's to change.
        actions: [
          if (!past)
            IconButton(
              tooltip: 'Add customers',
              onPressed: _addCustomers,
              icon: const Icon(Icons.person_add_alt_rounded),
            ),
        ],
      ),
      floatingActionButton: past
          ? null
          : FloatingActionButton.extended(
              onPressed: _addCustomers,
              icon: const Icon(Icons.add_rounded),
              label: const Text('Add customers'),
            ),
      body: _loading && _day == null
          ? const LoadingView()
          : _error != null
              ? ErrorView(message: _error!, onRetry: _load)
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(14, 10, 14, 96),
                    children: [
                      _summary(),
                      const SizedBox(height: 12),
                      if (_clients.isNotEmpty) _filters(),
                      if (_clients.isEmpty)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 40),
                          child: EmptyView(
                              icon: Icons.event_note_rounded, text: 'Nothing planned for this day yet'),
                        ),
                      for (final client in _shown) _clientRow(client),
                      if (_adhoc.isNotEmpty) ...[
                        const SizedBox(height: 18),
                        Row(
                          children: [
                            const Icon(Icons.bolt_rounded, size: 17, color: AppColors.warning),
                            const SizedBox(width: 6),
                            Text('Visited without being planned · ${_adhoc.length}',
                                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
                          ],
                        ),
                        const SizedBox(height: 4),
                        const Text('Called on anyway. Worth knowing when a plan keeps being overtaken.',
                            style: TextStyle(fontSize: 11.5, color: AppColors.muted)),
                        const SizedBox(height: 8),
                        for (final visit in _adhoc) _adhocRow(visit),
                      ],
                    ],
                  ),
                ),
    );
  }

  /// The day at a glance: how many, how far through, and how long it took.
  Widget _summary() {
    final planned = _clients.length;
    final done = _count('done') + _count('ongoing');
    final plans = ((_day?['plans'] as List?) ?? []).cast<Map<String, dynamic>>();
    final beats = plans
        .map((p) => (p['beat'] as Map?)?['name'])
        .whereType<String>()
        .toSet()
        .toList();
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      decoration: BoxDecoration(
        gradient: AppColors.brandGradient,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('$planned ${planned == 1 ? 'customer' : 'customers'} planned',
                        style: const TextStyle(
                            color: Colors.white, fontWeight: FontWeight.w900, fontSize: 19)),
                    const SizedBox(height: 3),
                    Text(
                      [
                        if (widget.memberName != null) widget.memberName!,
                        if (beats.isEmpty) 'Chosen customers' else beats.join(' · '),
                      ].join(' · '),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white70, fontSize: 12.5),
                    ),
                  ],
                ),
              ),
              Container(
                width: 54,
                height: 54,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2), shape: BoxShape.circle),
                child: Text('$done/$planned',
                    style: const TextStyle(
                        color: Colors.white, fontWeight: FontWeight.w900, fontSize: 14)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: LinearProgressIndicator(
              value: planned == 0 ? 0 : (done / planned).clamp(0.0, 1.0),
              minHeight: 6,
              backgroundColor: Colors.white24,
              valueColor: const AlwaysStoppedAnimation(Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  Widget _filters() {
    final chips = <(String, String, int)>[
      ('all', 'All', _clients.length),
      ('pending', 'To visit', _count('pending')),
      ('done', 'Visited', _count('done')),
      if (_missedCount > 0) ('missed', 'Missed', _missedCount),
      if (_count('cancelled') > 0) ('cancelled', 'Cancelled', _count('cancelled')),
    ];
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: SizedBox(
        height: 34,
        child: ListView(
          scrollDirection: Axis.horizontal,
          children: [
            for (final (key, label, count) in chips)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Material(
                  color: _filter == key ? AppColors.primary : Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(20),
                    onTap: () => setState(() => _filter = key),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
                      child: Text('$label  $count',
                          style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700,
                              color: _filter == key ? Colors.white : AppColors.text)),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _clientRow(Map<String, dynamic> c) {
    final past = DateUtils.dateOnly(widget.date).isBefore(DateUtils.dateOnly(DateTime.now()));
    // Planned for a day that has gone and not called on: that is a missed one, and it
    // is shown as one, in red, not left looking like something still to do.
    final status = '${c['visit_status']}' == 'pending' && past ? 'missed' : '${c['visit_status']}';
    final visit = c['visit'] as Map?;
    final (tint, label, icon) = switch (status) {
      'done' => (AppColors.success, 'Visited', Icons.check_rounded),
      'ongoing' => (AppColors.sky, 'At the customer', Icons.timelapse_rounded),
      'cancelled' => (AppColors.danger, 'Cancelled', Icons.close_rounded),
      'missed' => (AppColors.danger, 'Missed', Icons.report_gmailerrorred_rounded),
      _ => (AppColors.muted, 'To visit', Icons.radio_button_unchecked_rounded),
    };
    final beat = (c['route'] as Map?)?['name'];
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => Navigator.of(context)
              .push(MaterialPageRoute(builder: (_) => ClientDetailScreen(clientId: c['id'] as int)))
              .then((_) => _load()),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(11, 10, 11, 10),
            child: Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                      color: tint.withValues(alpha: 0.13), borderRadius: BorderRadius.circular(11)),
                  child: Icon(icon, size: 17, color: tint),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('${c['sequence'] ?? ''}. ${c['name']}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5)),
                      const SizedBox(height: 2),
                      Text(
                        [
                          label,
                          if (visit != null && visit['check_in_at'] != null)
                            '${fmtTime(visit['check_in_at'])}'
                                '${visit['check_out_at'] != null ? '-${fmtTime(visit['check_out_at'])}' : ''}',
                          if (beat != null) '$beat',
                          if (c['city'] != null) '${c['city']}',
                        ].join(' · '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 12, color: status == 'pending' ? AppColors.muted : tint),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right_rounded, size: 20, color: AppColors.muted),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _adhocRow(Map<String, dynamic> visit) {
    final client = visit['client'] as Map?;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: client == null
              ? null
              : () => Navigator.of(context)
                  .push(MaterialPageRoute(
                      builder: (_) => ClientDetailScreen(clientId: client['id'] as int)))
                  .then((_) => _load()),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(11, 10, 11, 10),
            child: Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                      color: AppColors.warning.withValues(alpha: 0.13),
                      borderRadius: BorderRadius.circular(11)),
                  child: const Icon(Icons.bolt_rounded, size: 17, color: AppColors.warning),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('${client?['name'] ?? 'Customer'}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5)),
                      Text(
                        [
                          'Not planned',
                          '${fmtTime(visit['check_in_at'])}'
                              '${visit['check_out_at'] != null ? '-${fmtTime(visit['check_out_at'])}' : ''}',
                          if ((visit['duration_min'] as num? ?? 0) > 0) '${visit['duration_min']} min',
                        ].join(' · '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12, color: AppColors.muted),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right_rounded, size: 20, color: AppColors.muted),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
