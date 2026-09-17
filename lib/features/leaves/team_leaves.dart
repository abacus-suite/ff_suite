import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../core/services.dart';
import '../../core/theme.dart';
import '../../widgets/common.dart';

const _months = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October',
  'November', 'December'];

/// Everyone in my team: balances, who is off today, and what is coming up.
class TeamLeavesScreen extends StatefulWidget {
  const TeamLeavesScreen({super.key});

  @override
  State<TeamLeavesScreen> createState() => _TeamLeavesScreenState();
}

class _TeamLeavesScreenState extends State<TeamLeavesScreen> {
  List<Map<String, dynamic>> _rows = [];
  bool _loading = true;
  String? _error;
  String _find = '';
  bool _offOnly = false;

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
      final list = (await Services.api.get('/api/v1/leaves/team') as List).cast<Map<String, dynamic>>();
      if (mounted) setState(() => _rows = list);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final needle = _find.trim().toLowerCase();
    final shown = _rows.where((r) {
      final e = r['employee'] as Map;
      if (_offOnly && r['on_leave_today'] == null) return false;
      return needle.isEmpty || '${e['name']} ${e['code'] ?? ''}'.toLowerCase().contains(needle);
    }).toList();
    final offToday = _rows.where((r) => r['on_leave_today'] != null).length;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Team Time Off'),
        actions: [
          IconButton(
            tooltip: 'Calendar',
            icon: const Icon(Icons.calendar_month_rounded),
            onPressed: () => Navigator.of(context)
                .push(MaterialPageRoute(builder: (_) => const LeaveCalendarScreen(team: true))),
          ),
        ],
      ),
      body: _loading && _rows.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : _error != null && _rows.isEmpty
              ? ErrorView(message: _error!, onRetry: _load)
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                    children: [
                      TextField(
                        onChanged: (v) => setState(() => _find = v),
                        decoration: const InputDecoration(
                            prefixIcon: Icon(Icons.search_rounded), hintText: 'Search team member', isDense: true),
                      ),
                      const SizedBox(height: 8),
                      Wrap(spacing: 6, children: [
                        ChoiceChip(label: Text('All (${_rows.length})'), selected: !_offOnly,
                            onSelected: (_) => setState(() => _offOnly = false)),
                        ChoiceChip(label: Text('Off today ($offToday)'), selected: _offOnly,
                            onSelected: (_) => setState(() => _offOnly = true)),
                      ]),
                      if (shown.isEmpty)
                        const EmptyView(icon: Icons.groups_rounded, text: 'Nobody here'),
                      for (final r in shown) _memberCard(r),
                    ],
                  ),
                ),
    );
  }

  Widget _memberCard(Map<String, dynamic> r) {
    final e = (r['employee'] as Map).cast<String, dynamic>();
    final off = (r['on_leave_today'] as Map?)?.cast<String, dynamic>();
    final upcoming = ((r['upcoming'] as List?) ?? []).cast<Map<String, dynamic>>();
    final types = ((r['types'] as List?) ?? []).cast<Map<String, dynamic>>();
    Widget figure(String label, num value, Color colour) => Expanded(
          child: Column(children: [
            Text(fmtQty(value), style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: colour)),
            Text(label, style: const TextStyle(fontSize: 11, color: AppColors.muted)),
          ]),
        );
    return Card(
      margin: const EdgeInsets.only(top: 10),
      child: ExpansionTile(
        leading: CircleAvatar(
          backgroundColor: (off != null ? AppColors.warning : AppColors.primary).withValues(alpha: 0.12),
          child: Icon(off != null ? Icons.beach_access_rounded : Icons.person_rounded,
              color: off != null ? AppColors.warning : AppColors.primary),
        ),
        title: Text('${e['name']}', style: const TextStyle(fontWeight: FontWeight.w800)),
        subtitle: Text(off != null
            ? 'On ${(off['type'] as Map)['name']} until ${off['to']}'
            : '${fmtQty(r['remaining'] as num? ?? 0)} days available'
                '${((r['pending'] as num?) ?? 0) > 0 ? ' · ${fmtQty(r['pending'] as num)} pending' : ''}'),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        children: [
          Row(children: [
            figure('Allocated', r['allocated'] as num? ?? 0, AppColors.primary),
            figure('Used', r['used'] as num? ?? 0, AppColors.purple),
            figure('Pending', r['pending'] as num? ?? 0, AppColors.warning),
            figure('Available', r['remaining'] as num? ?? 0, AppColors.success),
          ]),
          const Divider(height: 20),
          for (final t in types)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(children: [
                Expanded(child: Text('${t['name']}')),
                Text(
                  t['requires_allocation'] == true
                      ? '${fmtQty(t['used'] as num? ?? 0)} / ${fmtQty(t['allocated'] as num? ?? 0)} used'
                      : '${fmtQty(t['used'] as num? ?? 0)} used',
                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12.5),
                ),
              ]),
            ),
          if (upcoming.isNotEmpty) ...[
            const Divider(height: 20),
            const Align(
              alignment: Alignment.centerLeft,
              child: Text('Coming up', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5)),
            ),
            for (final l in upcoming)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(children: [
                  Expanded(
                    child: Text('${(l['type'] as Map)['name']} · ${l['from']}'
                        '${l['to'] != l['from'] ? ' → ${l['to']}' : ''}'),
                  ),
                  StatusBadge('${l['state']}', label: '${l['state_label']}'),
                ]),
              ),
          ],
        ],
      ),
    );
  }
}

/// A month grid of leave: mine, or my whole team's.
class LeaveCalendarScreen extends StatefulWidget {
  const LeaveCalendarScreen({super.key, this.team = false});

  final bool team;

  @override
  State<LeaveCalendarScreen> createState() => _LeaveCalendarScreenState();
}

class _LeaveCalendarScreenState extends State<LeaveCalendarScreen> {
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month, 1);
  List<Map<String, dynamic>> _leaves = [];
  bool _loading = true;
  String? _error;
  DateTime? _picked;

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
    final last = DateTime(_month.year, _month.month + 1, 0);
    try {
      final data = await Services.api.get('/api/v1/leaves/calendar', query: {
        'start': fmtDate(_month),
        'end': fmtDate(last),
        'member': widget.team ? 'team' : 'me',
      }) as Map<String, dynamic>;
      if (mounted) setState(() => _leaves = ((data['leaves'] as List?) ?? []).cast<Map<String, dynamic>>());
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<Map<String, dynamic>> _on(DateTime day) {
    final key = fmtDate(day);
    return _leaves.where((l) => '${l['from']}'.compareTo(key) <= 0 && '${l['to']}'.compareTo(key) >= 0).toList();
  }

  void _shift(int months) {
    setState(() {
      _month = DateTime(_month.year, _month.month + months, 1);
      _picked = null;
    });
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final days = DateTime(_month.year, _month.month + 1, 0).day;
    final lead = _month.weekday - 1;
    final picked = _picked;
    final pickedLeaves = picked == null ? const <Map<String, dynamic>>[] : _on(picked);
    return Scaffold(
      appBar: AppBar(title: Text(widget.team ? 'Team Leave Calendar' : 'My Leave Calendar')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 32),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 6, 8, 12),
                child: Column(children: [
                  Row(children: [
                    IconButton(onPressed: () => _shift(-1), icon: const Icon(Icons.chevron_left_rounded)),
                    Expanded(
                      child: Text('${_months[_month.month - 1]} ${_month.year}',
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                    ),
                    IconButton(onPressed: () => _shift(1), icon: const Icon(Icons.chevron_right_rounded)),
                  ]),
                  if (_loading) const LinearProgressIndicator(minHeight: 2),
                  Row(children: [
                    for (final d in const ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'])
                      Expanded(
                        child: Center(
                          child: Text(d,
                              style: const TextStyle(fontSize: 11.5, color: AppColors.muted, fontWeight: FontWeight.w700)),
                        ),
                      ),
                  ]),
                  const SizedBox(height: 6),
                  GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 7, mainAxisSpacing: 4, crossAxisSpacing: 4, childAspectRatio: 0.85),
                    itemCount: lead + days,
                    itemBuilder: (context, i) {
                      if (i < lead) return const SizedBox.shrink();
                      final day = DateTime(_month.year, _month.month, i - lead + 1);
                      final on = _on(day);
                      final approved = on.where((l) => l['state'] == 'validate').length;
                      final waiting = on.length - approved;
                      final selected = picked != null && fmtDate(picked) == fmtDate(day);
                      return InkWell(
                        borderRadius: BorderRadius.circular(10),
                        onTap: () => setState(() => _picked = selected ? null : day),
                        child: Container(
                          decoration: BoxDecoration(
                            color: on.isEmpty
                                ? Colors.white
                                : approved > 0
                                    ? const Color(0xFFFFF4D6)
                                    : const Color(0xFFEFF4FF),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                                color: selected ? AppColors.primary : const Color(0xFFE3E9F6), width: selected ? 2 : 1),
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text('${day.day}', style: const TextStyle(fontWeight: FontWeight.w800)),
                              if (on.isNotEmpty)
                                FittedBox(
                                  child: Text(
                                    widget.team
                                        ? '${on.length} off'
                                        : approved > 0
                                            ? 'Leave'
                                            : 'Waiting',
                                    style: TextStyle(
                                        fontSize: 10.5,
                                        fontWeight: FontWeight.w700,
                                        color: approved > 0 ? const Color(0xFFB7791F) : AppColors.primary),
                                  ),
                                ),
                              if (widget.team && waiting > 0 && approved > 0)
                                Text('$waiting wait', style: const TextStyle(fontSize: 9, color: AppColors.primary)),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 10),
                  const Wrap(spacing: 14, children: [
                    _Legend(colour: Color(0xFFFFF4D6), label: 'Approved'),
                    _Legend(colour: Color(0xFFEFF4FF), label: 'Waiting approval'),
                  ]),
                ]),
              ),
            ),
            if (_error != null) Padding(padding: const EdgeInsets.all(8), child: Text(_error!)),
            if (picked != null) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 12, 4, 6),
                child: Text('${fmtDate(picked)} · ${pickedLeaves.length} off',
                    style: const TextStyle(fontWeight: FontWeight.w800)),
              ),
              if (pickedLeaves.isEmpty)
                const Card(child: Padding(padding: EdgeInsets.all(16), child: Text('Nobody is off on this day'))),
              for (final l in pickedLeaves)
                Card(
                  child: ListTile(
                    title: Text(widget.team ? '${(l['employee'] as Map)['name']}' : '${(l['type'] as Map)['name']}',
                        style: const TextStyle(fontWeight: FontWeight.w700)),
                    subtitle: Text([
                      if (widget.team) (l['type'] as Map)['name'],
                      l['from'] == l['to'] ? '${l['from']}' : '${l['from']} → ${l['to']}',
                      if (l['half_day'] == true) l['half_day_period'] == 'pm' ? 'Afternoon' : 'Morning',
                    ].join(' · ')),
                    trailing: StatusBadge('${l['state']}', label: '${l['state_label']}'),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend({required this.colour, required this.label});

  final Color colour;
  final String label;

  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
              color: colour, borderRadius: BorderRadius.circular(3), border: Border.all(color: const Color(0xFFD5DCEB))),
        ),
        const SizedBox(width: 5),
        Text(label, style: const TextStyle(fontSize: 12, color: AppColors.muted)),
      ]);
}
