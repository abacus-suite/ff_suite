import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/format.dart';
import '../core/services.dart';
import '../core/theme.dart';
import 'common.dart';

/// A download icon for the title bar of an employee's own screen: choose the period (and the status) and the report of
/// that section is saved as an Excel sheet, without going through More > Reports.
class ReportDownloadButton extends StatelessWidget {
  const ReportDownloadButton({super.key, required this.reportKey, required this.title});

  /// The server's key of the report: 'expenses', 'samples', 'events', 'attendance', 'collections', 'receivables',
  /// 'tasks' or 'route_plans'.
  final String reportKey;
  final String title;

  @override
  Widget build(BuildContext context) => IconButton(
        tooltip: 'Download report',
        icon: const Icon(Icons.download_rounded),
        onPressed: () => showModalBottomSheet<void>(
          context: context,
          isScrollControlled: true,
          showDragHandle: true,
          builder: (_) => _ReportSheet(reportKey: reportKey, title: title),
        ),
      );
}

class _ReportSheet extends StatefulWidget {
  const _ReportSheet({required this.reportKey, required this.title});

  final String reportKey;
  final String title;

  @override
  State<_ReportSheet> createState() => _ReportSheetState();
}

class _ReportSheetState extends State<_ReportSheet> {
  static const _periods = [
    ('today', 'Today'),
    ('yesterday', 'Yesterday'),
    ('week', 'This week'),
    ('last_week', 'Last week'),
    ('month', 'This month'),
    ('last_month', 'Last month'),
    ('custom', 'Custom'),
  ];

  String _period = 'month';
  late DateTimeRange _range = _preset('month');
  String _member = 'me';
  String _status = 'all';
  List<String> _statuses = [];
  bool _loading = false;
  bool _busy = false;

  static DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

  DateTimeRange _preset(String key) {
    final today = _day(DateTime.now());
    final monday = today.subtract(Duration(days: today.weekday - 1));
    return switch (key) {
      'today' => DateTimeRange(start: today, end: today),
      'yesterday' => DateTimeRange(start: today.subtract(const Duration(days: 1)), end: today.subtract(const Duration(days: 1))),
      'week' => DateTimeRange(start: monday, end: today),
      'last_week' =>
        DateTimeRange(start: monday.subtract(const Duration(days: 7)), end: monday.subtract(const Duration(days: 1))),
      'last_month' => DateTimeRange(start: DateTime(today.year, today.month - 1, 1), end: DateTime(today.year, today.month, 0)),
      _ => DateTimeRange(start: DateTime(today.year, today.month, 1), end: today),
    };
  }

  /// A manager in Manager Mode can take the team's report too; an employee only has their own.
  bool get _canTeam => (Services.auth.profile?.isManager ?? false) && Services.managerMode.value;

  Map<String, dynamic> get _query => {'start': fmtDate(_range.start), 'end': fmtDate(_range.end), 'member': _member};

  @override
  void initState() {
    super.initState();
    _loadStatuses();
  }

  /// The statuses the report has in this period, for the filter.
  Future<void> _loadStatuses() async {
    setState(() => _loading = true);
    try {
      final data = await Services.api.get('/api/v1/reports/${widget.reportKey}', query: _query) as Map<String, dynamic>;
      final key = ((data['columns'] as List?) ?? [])
          .cast<Map<String, dynamic>>()
          .where((c) => c['type'] == 'status')
          .map((c) => c['key'])
          .firstOrNull;
      final found = <String>{
        if (key != null)
          for (final r in ((data['rows'] as List?) ?? []).cast<Map<String, dynamic>>())
            if (r[key] != null && '${r[key]}'.isNotEmpty) '${r[key]}',
      }.toList()
        ..sort();
      if (mounted) {
        setState(() {
          _statuses = found;
          if (!found.contains(_status)) _status = 'all';
        });
      }
    } catch (_) {
      if (mounted) setState(() => _statuses = []);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _choose(String key) async {
    if (key == 'custom') {
      final picked = await showDateRangePicker(
        context: context,
        firstDate: DateTime(2020),
        lastDate: DateTime.now().add(const Duration(days: 365)),
        initialDateRange: _range,
      );
      if (picked == null) return;
      setState(() {
        _period = 'custom';
        _range = picked;
      });
    } else {
      setState(() {
        _period = key;
        _range = _preset(key);
      });
    }
    _loadStatuses();
  }

  Future<void> _download() async {
    setState(() => _busy = true);
    try {
      final result = await Services.api.post('/api/v1/reports/${widget.reportKey}/export', {
        ..._query,
        if (_status != 'all') 'status': _status,
      }) as Map<String, dynamic>;
      final url = Uri.parse(await Services.api.url('${result['path']}'));
      // The phone's browser saves the sheet to Downloads and offers to open it.
      final opened = await launchUrl(url, mode: LaunchMode.externalApplication);
      if (!opened && mounted) showSnack(context, 'Could not open the download.');
      if (opened && mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) showProblem(context, e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${widget.title} report', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
            const SizedBox(height: 14),
            const Text('Period', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: AppColors.muted)),
            const SizedBox(height: 6),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final p in _periods)
                ChoiceChip(label: Text(p.$2), selected: _period == p.$1, onSelected: (_) => _choose(p.$1)),
            ]),
            const SizedBox(height: 6),
            Text('${fmtDate(_range.start)}  to  ${fmtDate(_range.end)}', style: const TextStyle(fontSize: 12, color: AppColors.muted)),
            if (_canTeam) ...[
              const SizedBox(height: 12),
              SegmentedButton<String>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(value: 'me', label: Text('Only me')),
                  ButtonSegment(value: 'team', label: Text('Me + my team')),
                ],
                selected: {_member},
                onSelectionChanged: (v) {
                  setState(() => _member = v.first);
                  _loadStatuses();
                },
              ),
            ],
            if (_statuses.isNotEmpty) ...[
              const SizedBox(height: 14),
              DropdownButtonFormField<String>(
                initialValue: _status,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Status'),
                items: [
                  const DropdownMenuItem(value: 'all', child: Text('All')),
                  for (final s in _statuses) DropdownMenuItem(value: s, child: Text(s)),
                ],
                onChanged: (v) => setState(() => _status = v ?? 'all'),
              ),
            ],
            if (_loading)
              const Padding(padding: EdgeInsets.only(top: 10), child: LinearProgressIndicator(minHeight: 2)),
            const SizedBox(height: 16),
            GradientButton(label: 'Download Excel', icon: Icons.download_rounded, busy: _busy, onPressed: _busy ? null : _download),
          ]),
        ),
      ),
    );
  }
}
