import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/format.dart';
import '../../core/services.dart';
import '../../core/theme.dart';
import '../../widgets/common.dart';

enum _View { list, table }

/// One report: pick the period and whose rows, read it as cards or a table,
/// and download it as an Excel sheet.
class ReportViewScreen extends StatefulWidget {
  const ReportViewScreen(
      {super.key,
      required this.report,
      required this.members,
      required this.canTeam});

  final Map<String, dynamic> report;
  final List<Map<String, dynamic>> members;
  final bool canTeam;

  @override
  State<ReportViewScreen> createState() => _ReportViewScreenState();
}

class _ReportViewScreenState extends State<ReportViewScreen> {
  late DateTimeRange _range;
  String _period = 'month';
  String _member = 'me';
  _View _view = _View.list;
  Map<String, dynamic>? _data;
  String? _error;
  bool _loading = true;
  bool _exporting = false;

  @override
  void initState() {
    super.initState();
    _range = _presetRange('month');
    _load();
  }

  static DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

  DateTimeRange _presetRange(String key) {
    final today = _day(DateTime.now());
    final monday = today.subtract(Duration(days: today.weekday - 1));
    return switch (key) {
      'today' => DateTimeRange(start: today, end: today),
      'yesterday' => DateTimeRange(
          start: today.subtract(const Duration(days: 1)),
          end: today.subtract(const Duration(days: 1))),
      'week' => DateTimeRange(start: monday, end: today),
      'last_week' => DateTimeRange(
          start: monday.subtract(const Duration(days: 7)),
          end: monday.subtract(const Duration(days: 1))),
      'last_month' => DateTimeRange(
          start: DateTime(today.year, today.month - 1, 1),
          end: DateTime(today.year, today.month, 0)),
      _ =>
        DateTimeRange(start: DateTime(today.year, today.month, 1), end: today),
    };
  }

  Map<String, dynamic> get _query => {
        'start': fmtDate(_range.start),
        'end': fmtDate(_range.end),
        'member': _member,
      };

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await Services.api
              .get('/api/v1/reports/${widget.report['key']}', query: _query)
          as Map<String, dynamic>;
      if (mounted) setState(() => _data = data);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _choosePeriod(String key) async {
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
        _range = _presetRange(key);
      });
    }
    _load();
  }

  Future<void> _chooseMember() async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheet) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.6,
        builder: (context, controller) => ListView(
          controller: controller,
          children: [
            _memberOption(sheet, 'me', Icons.person_rounded, 'Only me'),
            _memberOption(
                sheet, 'team', Icons.groups_rounded, 'Me and my whole team'),
            const Divider(),
            for (final m in widget.members)
              _memberOption(sheet, '${m['id']}', Icons.person_outline_rounded,
                  '${m['name']}',
                  subtitle: m['code'] as String?),
          ],
        ),
      ),
    );
    if (choice == null || choice == _member) return;
    setState(() => _member = choice);
    _load();
  }

  Widget _memberOption(
      BuildContext sheet, String value, IconData icon, String title,
      {String? subtitle}) {
    final selected = value == _member;
    return ListTile(
      leading: Icon(icon,
          color: selected ? AixoloColors.primary : AixoloColors.muted),
      title: Text(title,
          style: TextStyle(
              fontWeight: selected ? FontWeight.w800 : FontWeight.w500)),
      subtitle: subtitle == null ? null : Text(subtitle),
      trailing: selected
          ? const Icon(Icons.check_rounded, color: AixoloColors.primary)
          : null,
      onTap: () => Navigator.pop(sheet, value),
    );
  }

  String get _memberLabel => switch (_member) {
        'me' => 'Only me',
        'team' => 'Me + team',
        _ =>
          '${widget.members.where((m) => '${m['id']}' == _member).firstOrNull?['name'] ?? 'Employee'}',
      };

  Future<void> _export() async {
    setState(() => _exporting = true);
    try {
      final result = await Services.api
              .post('/api/v1/reports/${widget.report['key']}/export', _query)
          as Map<String, dynamic>;
      final url = Uri.parse(await Services.api.url('${result['path']}'));
      // The phone's browser saves the .xlsx to Downloads and offers to open it.
      final opened = await launchUrl(url, mode: LaunchMode.externalApplication);
      if (!opened && mounted)
        showSnack(context, 'Could not open the download.');
    } catch (e) {
      if (mounted) showSnack(context, e.toString());
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  // ------------------------------------------------------------------
  // Formatting
  // ------------------------------------------------------------------
  String _format(Map<String, dynamic> column, dynamic value) {
    if (value == null || value == '') return '–';
    final currency = _data?['currency'] as String?;
    return switch (column['type']) {
      'money' => fmtMoney(value as num, currency),
      'hours' => fmtHours(value as num),
      'km' => '${(value as num).toStringAsFixed(1)} km',
      'number' => fmtQty(value as num),
      'date' => _prettyDate('$value'),
      _ => '$value',
    };
  }

  static const _months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec'
  ];

  String _prettyDate(String iso) {
    final d = DateTime.tryParse(iso);
    return d == null ? iso : '${d.day} ${_months[d.month - 1]} ${d.year}';
  }

  Color _statusColour(String status) {
    final s = status.toLowerCase();
    if (s.contains('reject') ||
        s.contains('cancel') ||
        s.contains('refuse') ||
        s.contains('offsite')) {
      return AixoloColors.danger;
    }
    if (s.contains('approv') ||
        s.contains('received') ||
        s.contains('done') ||
        s.contains('onsite') ||
        s.contains('supplied') ||
        s.contains('sale') ||
        s.contains('validate') ||
        s.contains('checked out')) {
      return AixoloColors.success;
    }
    return AixoloColors.warning;
  }

  // ------------------------------------------------------------------
  // Build
  // ------------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    final data = _data;
    final columns =
        ((data?['columns'] as List?) ?? []).cast<Map<String, dynamic>>();
    final rows = ((data?['rows'] as List?) ?? []).cast<Map<String, dynamic>>();
    final totals =
        (data?['totals'] as Map?)?.cast<String, dynamic>() ?? const {};
    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.report['title']}'),
        actions: [
          IconButton(
            tooltip: _view == _View.list ? 'Table view' : 'List view',
            icon: Icon(_view == _View.list
                ? Icons.table_chart_rounded
                : Icons.view_agenda_rounded),
            onPressed: () => setState(
                () => _view = _view == _View.list ? _View.table : _View.list),
          ),
          IconButton(
            tooltip: 'Download Excel',
            icon: _exporting
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.download_rounded),
            onPressed: _exporting || rows.isEmpty ? null : _export,
          ),
        ],
      ),
      body: Column(
        children: [
          _filters(),
          if (_loading) const LinearProgressIndicator(minHeight: 2),
          if (totals.isNotEmpty && rows.isNotEmpty)
            _totals(columns, totals, rows.length),
          Expanded(
            child: _error != null
                ? ErrorView(message: _error!, onRetry: _load)
                // Columns arrive with the first answer; until then there is nothing to lay out.
                : columns.isEmpty
                    ? const Center(child: CircularProgressIndicator())
                    : rows.isEmpty && !_loading
                        ? const Center(
                            child: Text('Nothing in this period',
                                style: TextStyle(color: AixoloColors.muted)))
                        : RefreshIndicator(
                            onRefresh: _load,
                            child: _view == _View.list
                                ? _list(columns, rows)
                                : _table(columns, rows, totals),
                          ),
          ),
        ],
      ),
    );
  }

  Widget _filters() {
    const presets = [
      ('today', 'Today'),
      ('yesterday', 'Yesterday'),
      ('week', 'This week'),
      ('last_week', 'Last week'),
      ('month', 'This month'),
      ('last_month', 'Last month'),
      ('custom', 'Custom…'),
    ];
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            height: 46,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              children: [
                for (final p in presets)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: ChoiceChip(
                      label: Text(p.$1 == 'custom' && _period == 'custom'
                          ? '${_prettyDate(fmtDate(_range.start))} – ${_prettyDate(fmtDate(_range.end))}'
                          : p.$2),
                      selected: _period == p.$1,
                      onSelected: (_) => _choosePeriod(p.$1),
                    ),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                const Icon(Icons.event_rounded,
                    size: 16, color: AixoloColors.muted),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                      '${_prettyDate(fmtDate(_range.start))}  →  ${_prettyDate(fmtDate(_range.end))}',
                      style: const TextStyle(
                          color: AixoloColors.muted, fontSize: 12.5)),
                ),
                if (widget.canTeam)
                  ActionChip(
                    avatar: const Icon(Icons.people_alt_rounded,
                        size: 16, color: AixoloColors.primary),
                    label: Text(_memberLabel),
                    onPressed: _chooseMember,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _totals(List<Map<String, dynamic>> columns,
      Map<String, dynamic> totals, int count) {
    final items = [
      ('Records', '$count'),
      for (final c in columns)
        if (totals.containsKey(c['key']))
          ('${c['label']}', _format(c, totals[c['key']])),
    ];
    return SizedBox(
      height: 74,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
        children: [
          for (final item in items)
            Container(
              margin: const EdgeInsets.only(right: 8),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                    color: AixoloColors.border.withValues(alpha: 0.7)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(item.$1,
                      style: const TextStyle(
                          fontSize: 11, color: AixoloColors.muted)),
                  Text(item.$2,
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w800)),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _list(
      List<Map<String, dynamic>> columns, List<Map<String, dynamic>> rows) {
    // The first text-like columns make the card title; the rest are label/value pairs.
    final status = columns.where((c) => c['type'] == 'status').firstOrNull;
    final money = columns.where((c) => c['type'] == 'money').firstOrNull;
    final headline = columns.firstWhere((c) => c['key'] == 'customer',
        orElse: () => columns.firstWhere((c) => c['key'] == 'employee',
            orElse: () => columns.first));
    final rest = columns
        .where((c) => c != status && c != money && c != headline)
        .toList();
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
      itemCount: rows.length,
      itemBuilder: (context, i) {
        final row = rows[i];
        final statusText =
            status == null ? null : row[status['key']] as String?;
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(_format(headline, row[headline['key']]),
                          style: const TextStyle(
                              fontWeight: FontWeight.w800, fontSize: 15)),
                    ),
                    if (money != null)
                      Text(_format(money, row[money['key']]),
                          style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 15,
                              color: AixoloColors.primary)),
                  ],
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 14,
                  runSpacing: 6,
                  children: [
                    for (final c in rest)
                      if (row[c['key']] != null && row[c['key']] != '')
                        Text.rich(TextSpan(children: [
                          TextSpan(
                              text: '${c['label']}: ',
                              style: const TextStyle(
                                  color: AixoloColors.muted, fontSize: 12.5)),
                          TextSpan(
                              text: _format(c, row[c['key']]),
                              style: const TextStyle(
                                  fontWeight: FontWeight.w600, fontSize: 12.5)),
                        ])),
                  ],
                ),
                if (statusText != null && statusText.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                    decoration: BoxDecoration(
                      color: _statusColour(statusText).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(statusText,
                        style: TextStyle(
                            color: _statusColour(statusText),
                            fontSize: 12,
                            fontWeight: FontWeight.w700)),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _table(List<Map<String, dynamic>> columns,
      List<Map<String, dynamic>> rows, Map<String, dynamic> totals) {
    bool numeric(Map<String, dynamic> c) =>
        const {'money', 'hours', 'km', 'number'}.contains(c['type']);
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
      children: [
        Card(
          clipBehavior: Clip.antiAlias,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              headingRowColor: const WidgetStatePropertyAll(Color(0xFFE8EFFF)),
              headingTextStyle: const TextStyle(
                  fontWeight: FontWeight.w800,
                  color: AixoloColors.text,
                  fontSize: 13),
              dataTextStyle:
                  const TextStyle(color: AixoloColors.text, fontSize: 13),
              columnSpacing: 22,
              horizontalMargin: 14,
              columns: [
                for (final c in columns)
                  DataColumn(label: Text('${c['label']}'), numeric: numeric(c)),
              ],
              rows: [
                for (final row in rows)
                  DataRow(cells: [
                    for (final c in columns)
                      DataCell(c['type'] == 'status' &&
                              row[c['key']] != null &&
                              row[c['key']] != ''
                          ? Text('${row[c['key']]}',
                              style: TextStyle(
                                  color: _statusColour('${row[c['key']]}'),
                                  fontWeight: FontWeight.w700))
                          : Text(_format(c, row[c['key']]))),
                  ]),
                if (totals.isNotEmpty)
                  DataRow(
                    color: const WidgetStatePropertyAll(Color(0xFFF4F7FE)),
                    cells: [
                      for (var i = 0; i < columns.length; i++)
                        DataCell(Text(
                          i == 0
                              ? 'Total'
                              : totals.containsKey(columns[i]['key'])
                                  ? _format(
                                      columns[i], totals[columns[i]['key']])
                                  : '',
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        )),
                    ],
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
