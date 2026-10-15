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
    final format = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (sheet) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Download Employee Report', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
              const SizedBox(height: 6),
              Text('${widget.name} (${prettyShort(_start)} – ${prettyShort(_end)})',
                  style: const TextStyle(color: Color(0xFF64748B), fontSize: 13)),
              const SizedBox(height: 16),
              ListTile(
                leading: const CircleAvatar(
                    backgroundColor: Color(0xFFE8F7EE),
                    child: Icon(Icons.table_chart_outlined, color: Color(0xFF16A34A))),
                title: const Text('Excel Spreadsheet (.xlsx)', style: TextStyle(fontWeight: FontWeight.w700)),
                subtitle: const Text('Full performance report in Excel'),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12), side: const BorderSide(color: Color(0xFFE2E8F0))),
                onTap: () => Navigator.pop(sheet, 'excel'),
              ),
              const SizedBox(height: 10),
              ListTile(
                leading: const CircleAvatar(
                    backgroundColor: Color(0xFFEFF6FF),
                    child: Icon(Icons.picture_as_pdf_outlined, color: Color(0xFF2563EB))),
                title: const Text('PDF Document (.pdf)', style: TextStyle(fontWeight: FontWeight.w700)),
                subtitle: const Text('Download or print as PDF'),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12), side: const BorderSide(color: Color(0xFFE2E8F0))),
                onTap: () => Navigator.pop(sheet, 'pdf'),
              ),
            ],
          ),
        ),
      ),
    );
    if (format == null) return;

    setState(() => _exporting = true);
    try {
      final r = await Services.api.post('/api/v1/team/employee-report/export', {
        'member': widget.memberId,
        'start': fmtDate(_start),
        'end': fmtDate(_end),
        'format': format,
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
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (sheet) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.7),
          child: ListView(padding: const EdgeInsets.fromLTRB(20, 0, 20, 20), shrinkWrap: true, children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 17)),
            const SizedBox(height: 10),
            if (lines.isEmpty) const Text('Nothing for these dates.', style: TextStyle(color: AppColors.muted)),
            for (final l in lines)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 7),
                child: Row(
                  children: [
                    const Icon(Icons.circle, size: 6, color: Color(0xFF1E5BE3)),
                    const SizedBox(width: 10),
                    Expanded(child: Text(l, style: const TextStyle(fontSize: 13.5, color: Color(0xFF0F1B3D)))),
                  ],
                ),
              ),
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

    const cardBorder = Color(0xFFE2E8F0);

    Widget work({
      required IconData icon,
      required Color iconColor,
      required Color bg,
      required Color border,
      required String value,
      required String label,
      required VoidCallback onTap,
    }) =>
        Expanded(
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(12),
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 2.5),
              padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 3),
              decoration: BoxDecoration(
                color: bg,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: border),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, color: iconColor, size: 18),
                  const SizedBox(height: 4),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      value,
                      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: Color(0xFF0F1B3D)),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '$label ›',
                    style: const TextStyle(fontSize: 10, color: Color(0xFF64748B), fontWeight: FontWeight.w500),
                  ),
                ],
              ),
            ),
          ),
        );

    Widget box(IconData icon, Color iconColor, String label, String value, {VoidCallback? onTap}) => InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
            decoration: BoxDecoration(
              color: const Color(0xFFF1F5F9),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: cardBorder),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Icon(icon, color: iconColor, size: 22),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        label,
                        style: const TextStyle(fontSize: 11, color: Color(0xFF64748B), fontWeight: FontWeight.w500),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        value,
                        style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: Color(0xFF0F1B3D)),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );

    Widget detail(String label, List<String> values, String title) => Expanded(
          child: InkWell(
            onTap: values.isNotEmpty ? () => _list(title, values) : null,
            borderRadius: BorderRadius.circular(12),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: cardBorder),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: const TextStyle(fontSize: 11, color: Color(0xFF64748B), fontWeight: FontWeight.w500)),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          values.isEmpty ? '–' : values.first,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: Color(0xFF0F1B3D)),
                        ),
                      ),
                      if (values.length > 1)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(
                            color: const Color(0xFFE0EDFF),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            '+${values.length - 1}',
                            style: const TextStyle(fontWeight: FontWeight.w800, color: _blue, fontSize: 11),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );

    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Color(0xFF0F1B3D)),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('Employee report', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18, color: Color(0xFF0F1B3D))),
        centerTitle: false,
      ),
      body: _error != null
          ? ErrorView(message: _error!, onRetry: _load)
          : d == null
              ? const LoadingView()
              : ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 32), children: [
                  // 1. Employee header & dates
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: cardBorder),
                    ),
                    child: Row(children: [
                      CircleAvatar(
                        radius: 20,
                        backgroundColor: const Color(0xFFE0EDFF),
                        child: Text(initials(widget.name),
                            style: const TextStyle(fontWeight: FontWeight.w800, color: _blue, fontSize: 13)),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(widget.name.toUpperCase(),
                              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: Color(0xFF0F1B3D)),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis),
                          const SizedBox(height: 2),
                          Text('${prettyShort(_start)} – ${prettyShort(_end)}',
                              style: const TextStyle(fontSize: 11, color: Color(0xFF64748B), fontWeight: FontWeight.w500)),
                        ]),
                      ),
                      PopupMenuButton<String>(
                        onSelected: (v) => v == 'custom' ? _pickRange() : _preset(v),
                        itemBuilder: (_) => const [
                          PopupMenuItem(value: 'today', child: Text('Today')),
                          PopupMenuItem(value: 'week', child: Text('This week')),
                          PopupMenuItem(value: 'month', child: Text('This month')),
                          PopupMenuItem(value: 'custom', child: Text('Custom dates…')),
                        ],
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: const Color(0xFFCBD5E1), width: 1.2),
                          ),
                          child: Row(mainAxisSize: MainAxisSize.min, children: [
                            Container(
                              padding: const EdgeInsets.all(4),
                              decoration: BoxDecoration(
                                color: const Color(0xFFE0EDFF),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: const Icon(Icons.calendar_today_outlined, size: 13, color: _blue),
                            ),
                            const SizedBox(width: 6),
                            Text(_label, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12, color: Color(0xFF0F1B3D))),
                            const SizedBox(width: 2),
                            const Icon(Icons.keyboard_arrow_down_rounded, size: 16, color: Color(0xFF64748B)),
                          ]),
                        ),
                      ),
                    ]),
                  ),
                  const SizedBox(height: 10),

                  // 2. Territory and Route cards
                  Row(children: [
                    detail('Territory', territories, 'Territories'),
                    const SizedBox(width: 8),
                    detail('Route', routes, 'Routes'),
                  ]),
                  const SizedBox(height: 10),

                  // 3. Four work cards
                  Row(children: [
                    work(
                      icon: Icons.calendar_today_outlined,
                      iconColor: const Color(0xFF16A34A),
                      bg: const Color(0xFFE8F7EE),
                      border: const Color(0xFFA8E6CF),
                      value: '${d['days_worked'] ?? 0}',
                      label: 'Days worked',
                      onTap: () => _list('Days worked', [
                        for (final r in days)
                          '${r['date']}  ·  In ${r['in_at'] != null ? fmtTime(r['in_at']) : '-'}'
                              '  Out ${r['out_at'] != null ? fmtTime(r['out_at']) : '-'}  ·  ${_hours((r['hours'] as num?) ?? 0)}'
                      ]),
                    ),
                    work(
                      icon: Icons.schedule_rounded,
                      iconColor: const Color(0xFFEA580C),
                      bg: const Color(0xFFFFF2E8),
                      border: const Color(0xFFFFD5B8),
                      value: '${d['late_days'] ?? 0}',
                      label: 'Late days',
                      onTap: () => _list('Late days', [
                        for (final r in late) '${r['date']}  ·  In ${r['in_at'] != null ? fmtTime(r['in_at']) : '-'}'
                      ]),
                    ),
                    work(
                      icon: Icons.near_me_outlined,
                      iconColor: const Color(0xFF2563EB),
                      bg: const Color(0xFFEBF3FF),
                      border: const Color(0xFFBCD8FF),
                      value: '${((d['distance_km'] as num?) ?? 0).toStringAsFixed(0)} km',
                      label: 'Distance',
                      onTap: () => _list('Distance', [for (final r in days) '${r['date']}  ·  ${r['km']} km']),
                    ),
                    work(
                      icon: Icons.timer_outlined,
                      iconColor: const Color(0xFF059669),
                      bg: const Color(0xFFEAF8F2),
                      border: const Color(0xFFBCEAD5),
                      value: _hours((d['hours'] as num?) ?? 0),
                      label: 'Hours',
                      onTap: () => _list('Hours', [
                        for (final r in days) '${r['date']}  ·  ${_hours((r['hours'] as num?) ?? 0)}'
                      ]),
                    ),
                  ]),
                  const SizedBox(height: 12),

                  // 4. Metric Boxes (2-column Grid)
                  GridView.count(
                    crossAxisCount: 2,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    mainAxisSpacing: 10,
                    crossAxisSpacing: 10,
                    childAspectRatio: 2.2,
                    children: [
                      box(Icons.place_outlined, const Color(0xFF2563EB), 'Visits',
                          '${visits['done'] ?? 0} / ${visits['planned'] ?? 0} ›',
                          onTap: () => _list('Visits', [
                                for (final v in _rows(details['visits']))
                                  '${v['date']}  ·  ${(v['outlet'] as Map)['name']}  ·  ${v['done'] == true ? 'Visited' : 'Not visited'}'
                              ])),
                      box(Icons.check_circle_outline, const Color(0xFF16A34A), 'Tasks',
                          '${tasks['done'] ?? 0} / ${tasks['total'] ?? 0} ›',
                          onTap: () => _list('Tasks', [
                                for (final t in _rows(details['tasks']))
                                  '${t['name']}  ·  ${t['state']}${t['due'] != null ? '  ·  due ${t['due']}' : ''}'
                              ])),
                      box(Icons.bar_chart_rounded, const Color(0xFF2563EB), 'Bottles sold', '${d['bottles'] ?? 0}'),
                      box(Icons.storefront_outlined, const Color(0xFF0EA5E9), 'Onboarded outlets', '${d['outlets'] ?? 0}'),
                      box(Icons.shopping_cart_outlined, const Color(0xFF2563EB), 'POs to distributor',
                          '${d['pos_to_distributor'] ?? 0}'),
                      box(Icons.person_add_alt_1_outlined, const Color(0xFF2563EB), 'New leads', '${d['new_leads'] ?? 0}'),
                      box(Icons.receipt_long_outlined, const Color(0xFFF59E0B), 'Expenses',
                          fmtMoney(d['expenses'] as num?, d['currency'] as String?)),
                    ],
                  ),
                  const SizedBox(height: 18),

                  // 5. Download Report Button
                  DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF1E5BE3), Color(0xFF00C4B4)],
                        begin: Alignment.centerLeft,
                        end: Alignment.centerRight,
                      ),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(16),
                        onTap: _exporting ? null : _download,
                        child: Container(
                          height: 50,
                          alignment: Alignment.center,
                          child: _exporting
                              ? const SizedBox(
                                  width: 22,
                                  height: 22,
                                  child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5),
                                )
                              : const Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(Icons.file_download_outlined, color: Colors.white, size: 20),
                                    SizedBox(width: 8),
                                    Text(
                                      'Download report (Excel / PDF)',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 15,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ],
                                ),
                        ),
                      ),
                    ),
                  ),
                ]),
    );
  }
}

String prettyShort(DateTime d) => '${d.day} ${monthNames[d.month - 1].substring(0, 3)} ${d.year}';
