import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/format.dart';
import '../../core/services.dart';
import '../../core/theme.dart';
import '../../widgets/common.dart';
import '../../widgets/group_kit.dart';
import 'report_views.dart';
import 'summary_drill.dart';

enum _View { list, table, chart, pivot, calendar, map }

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
  String _groupBy = 'none';
  late String _by = _splits.isEmpty
      ? ''
      : widget.canTeam && _splits.any((x) => x['key'] == 'employee')
          ? 'employee'
          : '${_splits.first['key']}';
  String _status = 'all';
  String _find = '';
  final Set<String> _collapsed = {};
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

  /// How a report splits its rows (the summary report: overall, employee, day...).
  List<Map<String, dynamic>> get _splits => ((widget.report['by'] as List?) ?? []).cast<Map<String, dynamic>>();

  Map<String, dynamic> get _query => {
        'start': fmtDate(_range.start),
        'end': fmtDate(_range.end),
        'member': _member,
        if (_by.isNotEmpty) 'by': _by,
      };

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final path = '/api/v1/reports/${widget.report['key']}';
    final query = _query;
    // The last copy of this exact view draws at once; the fresh one replaces it.
    final saved = await Services.api.peek(path, query: query);
    if (mounted && saved is Map && _data == null) setState(() => _data = saved.cast<String, dynamic>());
    try {
      final data = await Services.api.get(path, query: query) as Map<String, dynamic>;
      if (!mounted || query['by'] != _query['by'] || query['start'] != _query['start'] ||
          query['member'] != _query['member']) {
        return; // the reader moved on while this was loading
      }
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
  // Filter and group (on the rows already loaded)
  // ------------------------------------------------------------------

  List<Map<String, dynamic>> _filtered(List<Map<String, dynamic>> columns, List<Map<String, dynamic>> rows) {
    final status = columns.where((c) => c['type'] == 'status').firstOrNull;
    final needle = _find.trim().toLowerCase();
    return rows.where((row) {
      if (_status != 'all' && status != null && '${row[status['key']]}' != _status) return false;
      if (needle.isEmpty) return true;
      return row.values.any((v) => v != null && '$v'.toLowerCase().contains(needle));
    }).toList();
  }

  Map<String, dynamic> _sumOf(List<Map<String, dynamic>> columns, List<Map<String, dynamic>> rows) => {
        for (final c in columns)
          if (c['total'] == true)
            c['key'] as String: rows.fold<double>(0, (sum, r) => sum + ((r[c['key']] as num?) ?? 0).toDouble()),
      };

  List<GroupOption> _groupOptions(List<Map<String, dynamic>> columns) {
    final keys = columns.map((c) => c['key']).toSet();
    const icons = {
      'employee': Icons.person_rounded,
      'customer': Icons.storefront_rounded,
      'route': Icons.route_rounded,
      'product': Icons.inventory_2_rounded,
      'category': Icons.category_rounded,
      'mode': Icons.payments_rounded,
      'city': Icons.location_city_rounded,
    };
    return [
      if (keys.contains('date')) ...dateGroups,
      for (final c in columns)
        if ((c['type'] == 'text' || c['type'] == 'status') &&
            !const {'number', 'reference', 'sku', 'phone', 'note', 'check_in', 'check_out', 'time'}.contains(c['key']))
          GroupOption('col:${c['key']}', '${c['label']}', icons[c['key']] ?? Icons.label_rounded),
    ];
  }

  List<(String, String, List<Map<String, dynamic>>)> _groups(List<Map<String, dynamic>> rows) {
    final titles = <String, String>{};
    final members = <String, List<Map<String, dynamic>>>{};
    for (final row in rows) {
      String key;
      String title;
      if (_groupBy.startsWith('col:')) {
        final value = row[_groupBy.substring(4)];
        title = (value == null || '$value'.isEmpty) ? '—' : '$value';
        key = title;
      } else {
        final date = DateTime.tryParse('${row['date']}');
        if (date == null) {
          key = '~';
          title = 'No date';
        } else {
          (key, title) = dateBucket(date, _groupBy);
        }
      }
      titles[key] = title;
      members.putIfAbsent(key, () => []).add(row);
    }
    final keys = titles.keys.toList();
    if (_groupBy.startsWith('col:')) {
      keys.sort((a, b) => members[b]!.length.compareTo(members[a]!.length));
    } else {
      keys.sort((a, b) => b.compareTo(a));
    }
    return [for (final k in keys) (k, titles[k]!, members[k]!)];
  }

  Widget _grouped(List<Map<String, dynamic>> columns, List<Map<String, dynamic>> rows) {
    final groups = _groups(rows);
    final money = columns.where((c) => c['total'] == true && c['type'] == 'money').toList();
    final counted = columns.where((c) => c['total'] == true && c['type'] != 'money').take(1).toList();
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
      children: [
        for (final g in groups) ...[
          GroupHeader(
            title: g.$2,
            count: g.$3.length,
            totals: [
              for (final c in [...money.take(1), ...counted])
                _format(c, _sumOf([c], g.$3)[c['key']]),
            ],
            expanded: !_collapsed.contains(g.$1),
            onTap: () => setState(() {
              if (!_collapsed.remove(g.$1)) _collapsed.add(g.$1);
            }),
          ),
          if (!_collapsed.contains(g.$1))
            _view != _View.table
                ? _list(columns, g.$3, nested: true)
                : _table(columns, g.$3, _sumOf(columns, g.$3), nested: true),
        ],
      ],
    );
  }

  // ------------------------------------------------------------------
  // Build
  // ------------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    final data = _data;
    final columns =
        ((data?['columns'] as List?) ?? []).cast<Map<String, dynamic>>();
    final allRows = ((data?['rows'] as List?) ?? []).cast<Map<String, dynamic>>();
    if ((_view == _View.map && !reportHasPlaces(allRows)) ||
        (_view == _View.calendar && columns.isNotEmpty && !reportHasDates(columns))) {
      _view = _View.list;
    }
    final rows = _filtered(columns, allRows);
    final filtering = _status != 'all' || _find.trim().isNotEmpty;
    final totals = filtering
        ? _sumOf(columns, rows)
        : (data?['totals'] as Map?)?.cast<String, dynamic>() ?? const <String, dynamic>{};
    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.report['title']}'),
        actions: [
          PopupMenuButton<_View>(
            tooltip: 'Change view',
            initialValue: _view,
            icon: Icon(_viewIcon(_view)),
            onSelected: (v) => setState(() => _view = v),
            itemBuilder: (_) => [
              for (final v in _View.values)
                if ((v != _View.map || reportHasPlaces(allRows)) &&
                    (v != _View.calendar || reportHasDates(columns)))
                  PopupMenuItem(
                    value: v,
                    child: Row(children: [
                      Icon(_viewIcon(v), size: 20, color: AixoloColors.primary),
                      const SizedBox(width: 10),
                      Text(_viewLabel(v)),
                    ]),
                  ),
            ],
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
          if (_splits.isNotEmpty) _splitBar(),
          if (columns.isNotEmpty) _refine(columns, allRows),
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
                            child: _view == _View.chart
                                ? ReportChartView(
                                    key: ValueKey('chart$_groupBy'),
                                    columns: columns,
                                    rows: rows,
                                    currency: data?['currency'] as String?,
                                    initialDimension: _groupBy)
                                : _view == _View.pivot
                                ? ReportPivotView(columns: columns, rows: rows, currency: data?['currency'] as String?)
                                : _view == _View.calendar
                                ? ReportCalendarView(
                                    reportKey: '${widget.report['key']}',
                                    columns: columns,
                                    rows: rows,
                                    start: _range.start,
                                    end: _range.end,
                                    onePerson: _member != 'team',
                                    format: _format)
                                : _view == _View.map
                                ? ReportMapView(
                                    columns: columns, rows: rows, currency: data?['currency'] as String?, format: _format)
                                : _groupBy == 'none' && _view == _View.list && widget.report['key'] == 'summary'
                                ? _summaryCards(rows, data?['currency'] as String?)
                                : _groupBy != 'none'
                                ? _grouped(columns, rows)
                                : _view == _View.list
                                    ? _list(columns, rows)
                                    : _table(columns, rows, totals),
                          ),
          ),
        ],
      ),
    );
  }

  // ------------------------------------------------------------------
  // Summary report as cards, with a way down to each person and day
  // ------------------------------------------------------------------
  String _memberIdFor(String name) {
    final profile = Services.auth.profile;
    if (profile != null && profile.name == name) return '${profile.employeeId}';
    return '${widget.members.where((m) => m['name'] == name).firstOrNull?['id'] ?? ''}';
  }

  Widget _summaryCards(List<Map<String, dynamic>> rows, String? currency) {
    final saleWord = (Services.auth.profile?.isDemandFlow ?? false) ? 'Demand' : 'Orders';
    if (_by == 'employee' || _by == 'overall') {
      return ListView(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
        children: [
          for (final (i, row) in rows.indexed)
            EmployeeSummaryCard(
              row: row,
              currency: currency,
              saleWord: saleWord,
              highlight: i == 0 && rows.length > 1,
              onTap: _by == 'overall'
                  ? null
                  : () {
                      final id = _memberIdFor('${row['employee']}');
                      if (id.isEmpty) return;
                      Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => EmployeeReportScreen(
                          memberId: id,
                          name: '${row['employee']}',
                          start: _range.start,
                          end: _range.end,
                        ),
                      ));
                    },
            ),
        ],
      );
    }
    if (_by == 'day') {
      return ListView(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
        children: [
          for (final row in rows)
            EmployeeSummaryCard(
              row: {...row, 'employee': _prettyDate('${row['date']}')},
              currency: currency,
              saleWord: saleWord,
              onTap: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => VisitDetailsScreen(
                  memberId: _member,
                  name: _memberLabel,
                  date: DateTime.parse('${row['date']}'),
                ),
              )),
            ),
        ],
      );
    }
    return _list(((_data?['columns'] as List?) ?? []).cast<Map<String, dynamic>>(), rows);
  }

  static IconData _viewIcon(_View v) => switch (v) {
        _View.list => Icons.view_agenda_rounded,
        _View.table => Icons.table_chart_rounded,
        _View.chart => Icons.bar_chart_rounded,
        _View.pivot => Icons.pivot_table_chart_rounded,
        _View.calendar => Icons.calendar_month_rounded,
        _View.map => Icons.map_rounded,
      };

  static String _viewLabel(_View v) => switch (v) {
        _View.list => 'List',
        _View.table => 'Table',
        _View.chart => 'Chart',
        _View.pivot => 'Pivot',
        _View.calendar => 'Calendar',
        _View.map => 'Map',
      };

  Widget _refine(List<Map<String, dynamic>> columns, List<Map<String, dynamic>> rows) {
    final status = columns.where((c) => c['type'] == 'status').firstOrNull;
    final values = status == null
        ? <String>[]
        : rows.map((r) => '${r[status['key']] ?? ''}').where((v) => v.isNotEmpty).toSet().toList();
    final options = _groupOptions(columns);
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      child: Column(
        children: [
          TextField(
            onChanged: (v) => setState(() => _find = v),
            decoration: const InputDecoration(
                prefixIcon: Icon(Icons.filter_list_rounded), hintText: 'Filter rows', isDense: true),
          ),
          const SizedBox(height: 6),
          SizedBox(
            height: 40,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                if (options.isNotEmpty)
                  GroupByChip(
                    value: _groupBy,
                    options: options,
                    onChanged: (v) => setState(() {
                      _groupBy = v;
                      _collapsed.clear();
                    }),
                  ),
                if (values.length > 1) ...[
                  const SizedBox(width: 6),
                  ChoiceChip(
                    label: const Text('All'),
                    selected: _status == 'all',
                    onSelected: (_) => setState(() => _status = 'all'),
                  ),
                  for (final v in values)
                    Padding(
                      padding: const EdgeInsets.only(left: 6),
                      child: ChoiceChip(
                        label: Text(v),
                        selected: _status == v,
                        onSelected: (_) => setState(() => _status = v),
                      ),
                    ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _splitBar() {
    return Container(
      color: Colors.white,
      height: 44,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(12, 2, 12, 6),
        children: [
          const Center(
            child: Padding(
              padding: EdgeInsets.only(right: 8),
              child: Text('Summary by', style: TextStyle(color: AixoloColors.muted, fontWeight: FontWeight.w700)),
            ),
          ),
          for (final split in _splits)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: ChoiceChip(
                label: Text('${split['label']}'),
                selected: _by == split['key'],
                onSelected: (_) {
                  if (_by == split['key']) return;
                  setState(() {
                    _by = '${split['key']}';
                    _data = null; // different columns: nothing old to show
                    _groupBy = 'none';
                    _status = 'all';
                  });
                  _load();
                },
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

  Widget _totals(List<Map<String, dynamic>> columns, Map<String, dynamic> totals, int count) {
    final items = [
      ('records', 'Records', '$count'),
      for (final c in columns)
        if (totals.containsKey(c['key'])) ('${c['key']}', '${c['label']}', _format(c, totals[c['key']])),
    ];
    return SizedBox(
      height: 82,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
        children: [
          for (final item in items)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: SizedBox(width: 150, child: MetricTile(metric: item.$1, label: item.$2, value: item.$3)),
            ),
        ],
      ),
    );
  }

  Widget _list(List<Map<String, dynamic>> columns, List<Map<String, dynamic>> rows, {bool nested = false}) {
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
      shrinkWrap: nested,
      physics: nested ? const NeverScrollableScrollPhysics() : null,
      padding: nested ? EdgeInsets.zero : const EdgeInsets.fromLTRB(12, 8, 12, 24),
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

  Widget _table(List<Map<String, dynamic>> columns, List<Map<String, dynamic>> rows, Map<String, dynamic> totals,
      {bool nested = false}) {
    bool numeric(Map<String, dynamic> c) =>
        const {'money', 'hours', 'km', 'number'}.contains(c['type']);
    return ListView(
      shrinkWrap: nested,
      physics: nested ? const NeverScrollableScrollPhysics() : null,
      padding: nested ? EdgeInsets.zero : const EdgeInsets.fromLTRB(12, 8, 12, 24),
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
