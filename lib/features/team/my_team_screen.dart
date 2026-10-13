import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/format.dart';
import '../../core/services.dart';
import '../../core/theme.dart';
import '../../widgets/common.dart';
import '../../widgets/skeleton.dart';
import '../home/manager_home.dart' show initials;

const _bg = Color(0xFFEEF3FB);
const _blue = Color(0xFF1D4ED8);

List<Map<String, dynamic>> _rows(dynamic v) => ((v as List?) ?? []).cast<Map<String, dynamic>>();

/// My Team: the team card (team, working, visits, bottles sold, overdue) and the people directly under the manager.
class MyTeamScreen extends StatefulWidget {
  const MyTeamScreen({super.key, this.rootId, this.rootName});

  final int? rootId;
  final String? rootName;

  @override
  State<MyTeamScreen> createState() => _MyTeamScreenState();
}

class _MyTeamScreenState extends State<MyTeamScreen> {
  String _range = 'month';
  DateTimeRange? _custom;
  Map<String, dynamic>? _data;
  String? _error;

  DateTimeRange get _dates {
    final today = DateUtils.dateOnly(DateTime.now());
    if (_custom != null) return _custom!;
    return switch (_range) {
      'today' => DateTimeRange(start: today, end: today),
      'week' => DateTimeRange(start: today.subtract(Duration(days: today.weekday - 1)), end: today),
      _ => DateTimeRange(start: DateTime(today.year, today.month, 1), end: today),
    };
  }

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
    setState(() => _error = null);
    try {
      final d = await Services.api.get('/api/v1/team/my', query: {
        'start': fmtDate(_dates.start),
        'end': fmtDate(_dates.end),
        if (widget.rootId != null) 'root': widget.rootId,
      }) as Map<String, dynamic>;
      if (mounted) setState(() => _data = d);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  Future<void> _pickRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2024),
      lastDate: DateTime.now(),
      initialDateRange: _dates,
    );
    if (picked != null) {
      setState(() => _custom = picked);
      _load();
    }
  }

  void _openReport(Map<String, dynamic> person) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => ManagerEmployeeReportScreen(
          memberId: person['id'] as int, name: '${person['name']}', start: _dates.start, end: _dates.end),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final d = _data;
    final manager = (d?['manager'] as Map?)?.cast<String, dynamic>();
    final people = _rows(d?['people']);
    final currency = d?['currency'] as String?;
    Widget stat(String value, String label) => Expanded(
          child: Container(
            margin: const EdgeInsets.all(4),
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.18), borderRadius: BorderRadius.circular(12)),
            child: Column(children: [
              FittedBox(
                  child: Text(value,
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 19))),
              Text(label, style: const TextStyle(color: Colors.white70, fontSize: 11)),
            ]),
          ),
        );
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg,
        automaticallyImplyLeading: widget.rootId != null,
        title: Text(widget.rootName ?? 'My Team', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 20)),
      ),
      body: _error != null
          ? ErrorView(message: _error!, onRetry: _load)
          : d == null
              ? const LoadingView()
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 100), children: [
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(children: [
                        InkWell(
                          onTap: _pickRange,
                          child: Container(
                            width: 38,
                            height: 38,
                            margin: const EdgeInsets.only(right: 8),
                            decoration: BoxDecoration(
                              color: _custom != null ? const Color(0xFFDBEAFE) : Colors.white,
                              borderRadius: BorderRadius.circular(19),
                              border: Border.all(color: _custom != null ? _blue : const Color(0xFFD5DEEE)),
                            ),
                            child: const Icon(Icons.calendar_month_rounded, size: 19, color: _blue),
                          ),
                        ),
                        for (final (k, label) in [('today', 'Today'), ('week', 'This week'), ('month', 'This month')])
                          Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: ChoiceChip(
                              label: Text(_custom == null && _range == k ? '✓ $label' : label,
                                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5)),
                              selected: _custom == null && _range == k,
                              showCheckmark: false,
                              selectedColor: const Color(0xFFDBEAFE),
                              onSelected: (_) {
                                setState(() {
                                  _range = k;
                                  _custom = null;
                                });
                                _load();
                              },
                            ),
                          ),
                      ]),
                    ),
                    const SizedBox(height: 12),
                    if (manager != null)
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(colors: [Color(0xFF1E40AF), Color(0xFF3B82F6)]),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Column(children: [
                          Row(children: [
                            CircleAvatar(
                              radius: 22,
                              backgroundColor: Colors.white,
                              child: Text(initials('${manager['name']}'),
                                  style: const TextStyle(fontWeight: FontWeight.w900, color: _blue)),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Text('${manager['name']}'.toUpperCase(),
                                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 16)),
                                Text('${manager['job'] ?? ''}'.toUpperCase(),
                                    style: const TextStyle(color: Colors.white70, fontSize: 11.5)),
                              ]),
                            ),
                          ]),
                          const SizedBox(height: 8),
                          Row(children: [
                            stat('${d['team']}', 'Team'),
                            stat('${d['working']}', 'Working'),
                            stat('${d['visits']}', 'Visits'),
                          ]),
                          Row(children: [
                            stat(fmtQty((d['bottles'] as num?) ?? 0), 'No. of bottles sold'),
                            stat(fmtMoney(d['overdue'] as num?, currency), 'Overdue'),
                          ]),
                        ]),
                      ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(2, 16, 0, 8),
                      child: Text('Directly under ${manager?['name'] ?? ''}'.toUpperCase(),
                          style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13)),
                    ),
                    if (people.isEmpty)
                      const Padding(
                        padding: EdgeInsets.all(24),
                        child: Center(child: Text('No one reports to you yet.', style: TextStyle(color: AppColors.muted))),
                      ),
                    for (final p in people)
                      InkWell(
                        onTap: () => _openReport(p),
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 10),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
                          child: Row(children: [
                            Stack(children: [
                              CircleAvatar(
                                radius: 22,
                                backgroundColor: const Color(0xFFDBEAFE),
                                child: Text(initials('${p['name']}'),
                                    style: const TextStyle(fontWeight: FontWeight.w900, color: _blue)),
                              ),
                              Positioned(
                                right: 0,
                                bottom: 0,
                                child: Container(
                                  width: 12,
                                  height: 12,
                                  decoration: BoxDecoration(
                                    color: p['working'] == true ? const Color(0xFF16A34A) : AppColors.muted,
                                    shape: BoxShape.circle,
                                    border: Border.all(color: Colors.white, width: 2),
                                  ),
                                ),
                              ),
                            ]),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Text('${p['name']}'.toUpperCase(),
                                    style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14)),
                                Text('${p['job'] ?? ''}'.toUpperCase(),
                                    style: const TextStyle(fontSize: 11, color: AppColors.muted)),
                                const SizedBox(height: 6),
                                Wrap(spacing: 6, children: [
                                  _pill('${p['visits']} visits'),
                                  _pill('${fmtQty((p['bottles'] as num?) ?? 0)} bottles'),
                                  if (((p['team_count'] as num?) ?? 0) > 0)
                                    InkWell(
                                      onTap: () => Navigator.of(context).push(MaterialPageRoute(
                                          builder: (_) => MyTeamScreen(rootId: p['id'] as int, rootName: '${p['name']}'))),
                                      child: _pill('${p['team_count']} in team ›'),
                                    ),
                                ]),
                              ]),
                            ),
                            const Icon(Icons.bar_chart_rounded, color: _blue),
                          ]),
                        ),
                      ),
                  ]),
                ),
    );
  }

  Widget _pill(String text) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
        decoration: BoxDecoration(color: const Color(0xFFEDE9FE), borderRadius: BorderRadius.circular(10)),
        child: Text(text, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFF5B21B6))),
      );
}

/// The Employee report in its new layout: dates, territory and route, four work buttons, boxes, download.
class ManagerEmployeeReportScreen extends StatefulWidget {
  const ManagerEmployeeReportScreen(
      {super.key, required this.memberId, required this.name, required this.start, required this.end});

  final int memberId;
  final String name;
  final DateTime start;
  final DateTime end;

  @override
  State<ManagerEmployeeReportScreen> createState() => _ManagerEmployeeReportScreenState();
}

class _ManagerEmployeeReportScreenState extends State<ManagerEmployeeReportScreen> {
  late DateTime _start = widget.start;
  late DateTime _end = widget.end;
  String _label = 'Custom';
  Map<String, dynamic>? _data;
  String? _error;
  bool _exporting = false;

  @override
  void initState() {
    super.initState();
    final today = DateUtils.dateOnly(DateTime.now());
    if (_start == today && _end == today) {
      _label = 'Today';
    } else if (_start == DateTime(today.year, today.month, 1) && _end == today) {
      _label = 'This month';
    } else if (_start == today.subtract(Duration(days: today.weekday - 1)) && _end == today) {
      _label = 'This week';
    }
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final d = await Services.api.get('/api/v1/team/employee-report', query: {
        'member': widget.memberId,
        'start': fmtDate(_start),
        'end': fmtDate(_end),
      }) as Map<String, dynamic>;
      if (mounted) setState(() => _data = d);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  void _preset(String key) {
    final today = DateUtils.dateOnly(DateTime.now());
    setState(() {
      _label = switch (key) {
        'today' => 'Today',
        'week' => 'This week',
        _ => 'This month',
      };
      _end = today;
      _start = switch (key) {
        'today' => today,
        'week' => today.subtract(Duration(days: today.weekday - 1)),
        _ => DateTime(today.year, today.month, 1),
      };
      _data = null;
    });
    _load();
  }

  Future<void> _pickRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2024),
      lastDate: DateTime.now(),
      initialDateRange: DateTimeRange(start: _start, end: _end),
    );
    if (picked != null) {
      setState(() {
        _start = picked.start;
        _end = picked.end;
        _label = 'Custom';
        _data = null;
      });
      _load();
    }
  }

  Future<void> _download() async {
    setState(() => _exporting = true);
    try {
      final r = await Services.api.post('/api/v1/team/employee-report/export', {
        'member': widget.memberId,
        'start': fmtDate(_start),
        'end': fmtDate(_end),
      }) as Map<String, dynamic>;
      final url = Uri.parse(await Services.api.url('${r['path']}'));
      final opened = await launchUrl(url, mode: LaunchMode.externalApplication);
      if (!opened && mounted) showSnack(context, 'Could not open the download.');
    } catch (e) {
      if (mounted) showProblem(context, e.toString());
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  void _list(String title, List<String> lines) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheet) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.7),
          child: ListView(padding: const EdgeInsets.fromLTRB(20, 0, 20, 20), shrinkWrap: true, children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 17)),
            const SizedBox(height: 8),
            if (lines.isEmpty) const Text('Nothing for these dates.', style: TextStyle(color: AppColors.muted)),
            for (final l in lines)
              Padding(padding: const EdgeInsets.symmetric(vertical: 6), child: Text(l)),
          ]),
        ),
      ),
    );
  }

  String _hours(num h) {
    final minutes = (h * 60).round();
    return '${minutes ~/ 60}h ${(minutes % 60).toString().padLeft(2, '0')}m';
  }

  @override
  Widget build(BuildContext context) {
    final d = _data;
    final details = (d?['details'] as Map?)?.cast<String, dynamic>() ?? const {};
    final territories = ((d?['territories'] as List?) ?? []).cast<String>();
    final routes = ((d?['routes'] as List?) ?? []).cast<String>();
    final visits = (d?['visits'] as Map?)?.cast<String, dynamic>() ?? const {};
    final tasks = (d?['tasks'] as Map?)?.cast<String, dynamic>() ?? const {};
    final days = _rows(details['days']);
    final late = _rows(details['late']);

    Widget work(IconData icon, Color tint, String value, String label, VoidCallback onTap) => Expanded(
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(14),
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 3),
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(color: tint.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(14)),
              child: Column(children: [
                Icon(icon, color: tint, size: 20),
                const SizedBox(height: 4),
                FittedBox(child: Text(value, style: TextStyle(fontWeight: FontWeight.w900, fontSize: 17, color: tint))),
                Text('$label ›', style: const TextStyle(fontSize: 10.5, color: AppColors.muted)),
              ]),
            ),
          ),
        );

    Widget box(IconData icon, Color tint, String label, String value, {VoidCallback? onTap}) => InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: tint.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(14)),
            child: Row(children: [
              Icon(icon, color: tint),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(label, style: const TextStyle(fontSize: 11.5, color: AppColors.muted)),
                  Text(value, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
                ]),
              ),
              if (onTap != null) const Icon(Icons.chevron_right_rounded, size: 18, color: AppColors.muted),
            ]),
          ),
        );

    Widget detail(String label, List<String> values, String title) => Expanded(
          child: InkWell(
            onTap: values.length > 1 ? () => _list(title, values) : null,
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 4),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
              child: Row(children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(label, style: const TextStyle(fontSize: 11, color: AppColors.muted)),
                    Text(values.isEmpty ? '–' : values.first,
                        maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w900)),
                  ]),
                ),
                if (values.length > 1)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(color: const Color(0xFFDBEAFE), borderRadius: BorderRadius.circular(10)),
                    child: Text('+${values.length - 1}',
                        style: const TextStyle(fontWeight: FontWeight.w900, color: _blue, fontSize: 12)),
                  ),
              ]),
            ),
          ),
        );

    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg,
        title: const Text('Employee report', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
      ),
      body: _error != null
          ? ErrorView(message: _error!, onRetry: _load)
          : d == null
              ? const LoadingView()
              : ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 32), children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
                    child: Row(children: [
                      CircleAvatar(
                        backgroundColor: const Color(0xFFDBEAFE),
                        child: Text(initials(widget.name),
                            style: const TextStyle(fontWeight: FontWeight.w900, color: _blue)),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(widget.name.toUpperCase(), style: const TextStyle(fontWeight: FontWeight.w900)),
                          Text('${prettyShort(_start)} – ${prettyShort(_end)}',
                              style: const TextStyle(fontSize: 11.5, color: AppColors.muted)),
                        ]),
                      ),
                      PopupMenuButton<String>(
                        onSelected: (v) => v == 'custom' ? _pickRange() : _preset(v),
                        itemBuilder: (_) => const [
                          PopupMenuItem(value: 'today', child: Text('Today')),
                          PopupMenuItem(value: 'week', child: Text('This week')),
                          PopupMenuItem(value: 'month', child: Text('This month')),
                          PopupMenuItem(value: 'custom', child: Text('Choose dates…')),
                        ],
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                          decoration: BoxDecoration(
                              color: const Color(0xFFEEF3FB), borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: _blue)),
                          child: Row(mainAxisSize: MainAxisSize.min, children: [
                            const Icon(Icons.calendar_month_rounded, size: 18, color: _blue),
                            const SizedBox(width: 6),
                            Text(_label, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5)),
                            const Icon(Icons.keyboard_arrow_down_rounded, size: 18),
                          ]),
                        ),
                      ),
                    ]),
                  ),
                  const SizedBox(height: 10),
                  Row(children: [
                    detail('Territory', territories, 'Territories'),
                    detail('Route', routes, 'Routes'),
                  ]),
                  const SizedBox(height: 10),
                  Row(children: [
                    work(Icons.event_available_rounded, const Color(0xFF16A34A), '${d['days_worked']}', 'Days worked',
                        () => _list('Days worked', [
                              for (final r in days)
                                '${r['date']}  ·  In ${r['in_at'] != null ? fmtTime(r['in_at']) : '-'}'
                                    '  Out ${r['out_at'] != null ? fmtTime(r['out_at']) : '-'}  ·  ${_hours((r['hours'] as num?) ?? 0)}'
                            ])),
                    work(Icons.schedule_rounded, const Color(0xFFEA580C), '${d['late_days']}', 'Late days',
                        () => _list('Late days', [
                              for (final r in late) '${r['date']}  ·  In ${r['in_at'] != null ? fmtTime(r['in_at']) : '-'}'
                            ])),
                    work(Icons.route_rounded, const Color(0xFF2563EB), '${((d['distance_km'] as num?) ?? 0).toStringAsFixed(0)} km',
                        'Distance',
                        () => _list('Distance', [for (final r in days) '${r['date']}  ·  ${r['km']} km'])),
                    work(Icons.timer_rounded, const Color(0xFF7C3AED), _hours((d['hours'] as num?) ?? 0), 'Hours',
                        () => _list('Hours', [
                              for (final r in days) '${r['date']}  ·  ${_hours((r['hours'] as num?) ?? 0)}'
                            ])),
                  ]),
                  const SizedBox(height: 12),
                  GridView.count(
                    crossAxisCount: 2,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    mainAxisSpacing: 10,
                    crossAxisSpacing: 10,
                    childAspectRatio: 2.3,
                    children: [
                      box(Icons.place_rounded, const Color(0xFF2563EB), 'Visits', '${visits['done']} / ${visits['planned']}',
                          onTap: () => _list('Visits', [
                                for (final v in _rows(details['visits']))
                                  '${v['date']}  ·  ${(v['outlet'] as Map)['name']}  ·  ${v['done'] == true ? 'Visited' : 'Not visited'}'
                              ])),
                      box(Icons.check_circle_rounded, const Color(0xFF16A34A), 'Tasks', '${tasks['done']} / ${tasks['total']}',
                          onTap: () => _list('Tasks', [
                                for (final t in _rows(details['tasks']))
                                  '${t['name']}  ·  ${t['state']}${t['due'] != null ? '  ·  due ${t['due']}' : ''}'
                              ])),
                      box(Icons.local_drink_rounded, const Color(0xFF2563EB), 'Bottles sold', '${d['bottles']}'),
                      box(Icons.storefront_rounded, const Color(0xFF16A34A), 'Onboarded outlets', '${d['outlets']}'),
                      box(Icons.local_shipping_rounded, const Color(0xFFD97706), 'POs to distributor',
                          '${d['pos_to_distributor']}'),
                      box(Icons.person_add_alt_1_rounded, const Color(0xFF2563EB), 'New leads', '${d['new_leads']}'),
                      box(Icons.receipt_long_rounded, const Color(0xFFDC2626), 'Expenses',
                          fmtMoney(d['expenses'] as num?, d['currency'] as String?)),
                    ],
                  ),
                  const SizedBox(height: 16),
                  GradientButton(
                    label: 'Download report (Excel)',
                    icon: Icons.download_rounded,
                    busy: _exporting,
                    onPressed: _exporting ? null : _download,
                  ),
                ]),
    );
  }
}

String prettyShort(DateTime d) => '${d.day} ${monthNames[d.month - 1].substring(0, 3)} ${d.year}';
