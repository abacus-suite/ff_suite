import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' hide Path;

import '../../core/format.dart';
import '../../core/theme.dart';
import '../../widgets/group_kit.dart';
import '../../widgets/map.dart';

const _palette = [
  Color(0xFF1A56DB), Color(0xFF16A34A), Color(0xFFF59E0B), Color(0xFF7C5CFC), Color(0xFF0D9488),
  Color(0xFFDC2626), Color(0xFF0EA5E9), Color(0xFFDB2777), Color(0xFF65A30D), Color(0xFF9333EA),
];

/// A way to split rows: a column's value, or a date bucket.
class Dimension {
  const Dimension(this.key, this.label);

  final String key; // 'col:<column>' or day / week / month / year
  final String label;

  (String, String) of(Map<String, dynamic> row) {
    if (key.startsWith('col:')) {
      final value = row[key.substring(4)];
      final text = (value == null || '$value'.isEmpty) ? '—' : '$value';
      return (text, text);
    }
    final date = DateTime.tryParse('${row['date']}');
    if (date == null) return ('~', 'No date');
    return dateBucket(date, key);
  }

  bool get isDate => !key.startsWith('col:');
}

/// What gets added up: a total column, or a plain count of rows.
class Measure {
  const Measure(this.key, this.label, this.column);

  final String key; // column key, or '#' for count
  final String label;
  final Map<String, dynamic>? column;

  double of(Map<String, dynamic> row) => key == '#' ? 1 : ((row[key] as num?) ?? 0).toDouble();
}

List<Dimension> dimensionsFor(List<Map<String, dynamic>> columns) {
  final keys = columns.map((c) => c['key']).toSet();
  return [
    if (keys.contains('date')) ...[
      const Dimension('day', 'Day'),
      const Dimension('week', 'Week'),
      const Dimension('month', 'Month'),
      const Dimension('year', 'Year'),
    ],
    for (final c in columns)
      if ((c['type'] == 'text' || c['type'] == 'status') &&
          !const {'number', 'reference', 'sku', 'phone', 'note', 'check_in', 'check_out', 'time', 'first', 'last'}
              .contains(c['key']))
        Dimension('col:${c['key']}', '${c['label']}'),
  ];
}

List<Measure> measuresFor(List<Map<String, dynamic>> columns) => [
      for (final c in columns)
        if (c['total'] == true) Measure('${c['key']}', '${c['label']}', c),
      const Measure('#', 'Count', null),
    ];

String formatMeasure(Measure m, double value, String? currency) {
  final type = m.column?['type'];
  if (type == 'money') return fmtMoney(value, currency);
  if (type == 'km') return '${value.toStringAsFixed(1)} km';
  if (type == 'hours') return fmtHours(value);
  return fmtQty(value);
}

String _short(double value, String? type) {
  final prefix = type == 'money' ? '₹' : '';
  if (value.abs() >= 10000000) return '$prefix${(value / 10000000).toStringAsFixed(1)}Cr';
  if (value.abs() >= 100000) return '$prefix${(value / 100000).toStringAsFixed(1)}L';
  if (value.abs() >= 1000) return '$prefix${(value / 1000).toStringAsFixed(1)}K';
  return '$prefix${fmtQty(value)}';
}

/// Sorted (key, label, value) groups.
List<(String, String, double)> aggregate(List<Map<String, dynamic>> rows, Dimension d, Measure m) {
  final labels = <String, String>{};
  final sums = <String, double>{};
  for (final row in rows) {
    final (key, label) = d.of(row);
    labels[key] = label;
    sums[key] = (sums[key] ?? 0) + m.of(row);
  }
  final keys = labels.keys.toList();
  if (d.isDate) {
    keys.sort();
  } else {
    keys.sort((a, b) => sums[b]!.compareTo(sums[a]!));
  }
  return [for (final k in keys) (k, labels[k]!, sums[k]!)];
}

Widget _pickerChip<T>(
    BuildContext context, String prefix, T value, List<T> options, String Function(T) label, ValueChanged<T> onChanged) {
  return PopupMenuButton<T>(
    initialValue: value,
    onSelected: onChanged,
    itemBuilder: (_) => [for (final o in options) PopupMenuItem(value: o, child: Text(label(o)))],
    child: Chip(
      avatar: const Icon(Icons.arrow_drop_down_rounded, size: 18, color: AppColors.primary),
      label: Text('$prefix${label(value)}'),
    ),
  );
}

// ======================================================================
// Chart
// ======================================================================
enum ChartKind { bar, line, pie }

class ReportChartView extends StatefulWidget {
  const ReportChartView({super.key, required this.columns, required this.rows, this.currency, this.initialDimension});

  final List<Map<String, dynamic>> columns;
  final List<Map<String, dynamic>> rows;
  final String? currency;
  final String? initialDimension;

  @override
  State<ReportChartView> createState() => _ReportChartViewState();
}

class _ReportChartViewState extends State<ReportChartView> {
  late List<Dimension> _dims = dimensionsFor(widget.columns);
  late List<Measure> _measures = measuresFor(widget.columns);
  late Dimension _dim = _pickDim();
  late Measure _measure = _measures.firstWhere((m) => m.column?['type'] == 'money', orElse: () => _measures.first);
  late ChartKind _kind = _dim.isDate ? ChartKind.line : ChartKind.bar;

  Dimension _pickDim() {
    final wanted = widget.initialDimension;
    if (wanted != null && wanted != 'none') {
      final found = _dims.where((d) => d.key == wanted).firstOrNull;
      if (found != null) return found;
    }
    return _dims.firstWhere((d) => d.key == 'col:employee',
        orElse: () => _dims.firstWhere((d) => d.key == 'col:customer',
            orElse: () => _dims.firstWhere((d) => d.key == 'day', orElse: () => _dims.first)));
  }

  @override
  void didUpdateWidget(covariant ReportChartView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.columns != widget.columns) {
      _dims = dimensionsFor(widget.columns);
      _measures = measuresFor(widget.columns);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_dims.isEmpty) {
      return const Center(child: Text('This report has nothing to chart.', style: TextStyle(color: AppColors.muted)));
    }
    var groups = aggregate(widget.rows, _dim, _measure);
    final type = _measure.column?['type'] as String?;
    if (_kind == ChartKind.pie && groups.length > 8) {
      final rest = groups.skip(7).fold<double>(0, (s, g) => s + g.$3);
      groups = [...groups.take(7), ('~', 'Others', rest)];
    }
    if (_kind == ChartKind.bar && groups.length > 15) groups = groups.take(15).toList();
    final total = groups.fold<double>(0, (s, g) => s + g.$3);
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
      children: [
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            _pickerChip(context, 'By ', _dim, _dims, (d) => d.label, (d) {
              setState(() {
                _dim = d;
                if (d.isDate && _kind == ChartKind.pie) _kind = ChartKind.line;
              });
            }),
            _pickerChip(context, '', _measure, _measures, (m) => m.label, (m) => setState(() => _measure = m)),
            SegmentedButton<ChartKind>(
              showSelectedIcon: false,
              style: const ButtonStyle(visualDensity: VisualDensity.compact),
              segments: const [
                ButtonSegment(value: ChartKind.bar, icon: Icon(Icons.bar_chart_rounded)),
                ButtonSegment(value: ChartKind.line, icon: Icon(Icons.show_chart_rounded)),
                ButtonSegment(value: ChartKind.pie, icon: Icon(Icons.pie_chart_rounded)),
              ],
              selected: {_kind},
              onSelectionChanged: (v) => setState(() => _kind = v.first),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: groups.isEmpty
                ? const SizedBox(height: 160, child: Center(child: Text('Nothing to show')))
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('${_measure.label} by ${_dim.label.toLowerCase()}',
                          style: const TextStyle(fontWeight: FontWeight.w800)),
                      Text('Total ${formatMeasure(_measure, total, widget.currency)}',
                          style: const TextStyle(color: AppColors.muted, fontSize: 12.5)),
                      const SizedBox(height: 14),
                      switch (_kind) {
                        ChartKind.pie => _PieChart(groups: groups, total: total, format: (v) => formatMeasure(_measure, v, widget.currency)),
                        ChartKind.line => SizedBox(
                            height: 220,
                            child: CustomPaint(
                              size: Size.infinite,
                              painter: _LinePainter(groups, (v) => _short(v, type)),
                            ),
                          ),
                        ChartKind.bar => _BarList(groups: groups, format: (v) => formatMeasure(_measure, v, widget.currency)),
                      },
                    ],
                  ),
          ),
        ),
      ],
    );
  }
}

class _BarList extends StatelessWidget {
  const _BarList({required this.groups, required this.format});

  final List<(String, String, double)> groups;
  final String Function(double) format;

  @override
  Widget build(BuildContext context) {
    final top = groups.fold<double>(0, (m, g) => math.max(m, g.$3.abs()));
    return Column(
      children: [
        for (var i = 0; i < groups.length; i++)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 5),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                        child: Text(groups[i].$2,
                            maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12.5))),
                    Text(format(groups[i].$3), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5)),
                  ],
                ),
                const SizedBox(height: 4),
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(
                    minHeight: 10,
                    value: top == 0 ? 0 : (groups[i].$3.abs() / top).clamp(0.0, 1.0),
                    backgroundColor: AppColors.border,
                    color: _palette[i % _palette.length],
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _LinePainter extends CustomPainter {
  _LinePainter(this.groups, this.short);

  final List<(String, String, double)> groups;
  final String Function(double) short;

  @override
  void paint(Canvas canvas, Size size) {
    const left = 44.0, bottom = 26.0, top = 10.0;
    final width = size.width - left - 8;
    final height = size.height - bottom - top;
    final maxValue = groups.fold<double>(0, (m, g) => math.max(m, g.$3));
    final ceiling = maxValue <= 0 ? 1.0 : maxValue * 1.15;
    final grid = Paint()..color = const Color(0xFFE3E9F6)..strokeWidth = 1;
    final text = TextPainter(textDirection: TextDirection.ltr);
    for (var i = 0; i <= 4; i++) {
      final y = top + height - height * i / 4;
      canvas.drawLine(Offset(left, y), Offset(left + width, y), grid);
      text.text = TextSpan(text: short(ceiling * i / 4), style: const TextStyle(fontSize: 10, color: AppColors.muted));
      text.layout();
      text.paint(canvas, Offset(left - text.width - 6, y - text.height / 2));
    }
    if (groups.isEmpty) return;
    final step = groups.length == 1 ? 0.0 : width / (groups.length - 1);
    Offset point(int i) => Offset(left + (groups.length == 1 ? width / 2 : step * i), top + height - height * (groups[i].$3 / ceiling));
    final path = Path()..moveTo(point(0).dx, point(0).dy);
    for (var i = 1; i < groups.length; i++) {
      path.lineTo(point(i).dx, point(i).dy);
    }
    final fill = Path.from(path)
      ..lineTo(point(groups.length - 1).dx, top + height)
      ..lineTo(point(0).dx, top + height)
      ..close();
    canvas.drawPath(
        fill,
        Paint()
          ..shader = const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0x551A56DB), Color(0x001A56DB)],
          ).createShader(Rect.fromLTWH(left, top, width, height)));
    canvas.drawPath(path, Paint()
      ..color = AppColors.primary
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke);
    final every = math.max(1, (groups.length / 6).ceil());
    for (var i = 0; i < groups.length; i++) {
      canvas.drawCircle(point(i), 3, Paint()..color = AppColors.primary);
      if (i % every == 0 || i == groups.length - 1) {
        text.text = TextSpan(text: groups[i].$2, style: const TextStyle(fontSize: 9.5, color: AppColors.muted));
        text.layout(maxWidth: 70);
        text.paint(canvas, Offset((point(i).dx - text.width / 2).clamp(0, size.width - text.width), top + height + 6));
      }
    }
  }

  @override
  bool shouldRepaint(covariant _LinePainter old) => old.groups != groups;
}

class _PieChart extends StatelessWidget {
  const _PieChart({required this.groups, required this.total, required this.format});

  final List<(String, String, double)> groups;
  final double total;
  final String Function(double) format;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SizedBox(
          height: 190,
          child: CustomPaint(size: Size.infinite, painter: _PiePainter(groups.map((g) => g.$3).toList())),
        ),
        const SizedBox(height: 12),
        for (var i = 0; i < groups.length; i++)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(
              children: [
                Container(width: 12, height: 12, decoration: BoxDecoration(color: _palette[i % _palette.length], shape: BoxShape.circle)),
                const SizedBox(width: 8),
                Expanded(child: Text(groups[i].$2, maxLines: 1, overflow: TextOverflow.ellipsis)),
                Text('${total == 0 ? 0 : (groups[i].$3 * 100 / total).round()}%',
                    style: const TextStyle(color: AppColors.muted, fontSize: 12)),
                const SizedBox(width: 10),
                Text(format(groups[i].$3), style: const TextStyle(fontWeight: FontWeight.w800)),
              ],
            ),
          ),
      ],
    );
  }
}

class _PiePainter extends CustomPainter {
  _PiePainter(this.values);

  final List<double> values;

  @override
  void paint(Canvas canvas, Size size) {
    final total = values.fold<double>(0, (s, v) => s + math.max(v, 0));
    if (total <= 0) return;
    final radius = math.min(size.width, size.height) / 2;
    final rect = Rect.fromCircle(center: size.center(Offset.zero), radius: radius);
    var start = -math.pi / 2;
    for (var i = 0; i < values.length; i++) {
      final sweep = math.max(values[i], 0) / total * 2 * math.pi;
      canvas.drawArc(rect, start, sweep, false, Paint()
        ..color = _palette[i % _palette.length]
        ..style = PaintingStyle.stroke
        ..strokeWidth = radius * 0.42);
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(covariant _PiePainter old) => old.values != values;
}

// ======================================================================
// Pivot
// ======================================================================
class ReportPivotView extends StatefulWidget {
  const ReportPivotView({super.key, required this.columns, required this.rows, this.currency});

  final List<Map<String, dynamic>> columns;
  final List<Map<String, dynamic>> rows;
  final String? currency;

  @override
  State<ReportPivotView> createState() => _ReportPivotViewState();
}

class _ReportPivotViewState extends State<ReportPivotView> {
  late final List<Dimension> _dims = dimensionsFor(widget.columns);
  late final List<Measure> _measures = measuresFor(widget.columns);
  late Dimension _rowsBy = _dims.firstWhere((d) => d.key == 'col:employee',
      orElse: () => _dims.firstWhere((d) => !d.isDate, orElse: () => _dims.first));
  late Dimension _colsBy = _dims.firstWhere((d) => d.key == 'week' && d != _rowsBy,
      orElse: () => _dims.firstWhere((d) => d.key == 'col:status', orElse: () => _dims.last));
  late Measure _measure = _measures.firstWhere((m) => m.column?['type'] == 'money', orElse: () => _measures.first);

  static const _cellWidth = 104.0;
  static const _labelWidth = 140.0;
  static const _rowHeight = 44.0;

  Widget _cell(String text,
      {double width = _cellWidth,
      bool bold = false,
      bool left = false,
      Color? background,
      Color? colour,
      bool header = false}) {
    return Container(
      width: width,
      height: _rowHeight,
      alignment: left ? Alignment.centerLeft : Alignment.centerRight,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: background,
        border: const Border(
          right: BorderSide(color: Color(0xFFE3E9F6)),
          bottom: BorderSide(color: Color(0xFFE3E9F6)),
        ),
      ),
      child: Text(
        text,
        maxLines: header ? 2 : 1,
        overflow: TextOverflow.ellipsis,
        textAlign: left ? TextAlign.left : TextAlign.right,
        style: TextStyle(
          fontSize: 12.5,
          fontWeight: bold ? FontWeight.w800 : FontWeight.w500,
          color: colour ?? AppColors.text,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_dims.length < 2) {
      return const Center(
          child: Text('This report has nothing to cross-tabulate.', style: TextStyle(color: AppColors.muted)));
    }
    final rowGroups = aggregate(widget.rows, _rowsBy, _measure);
    final colGroups = aggregate(widget.rows, _colsBy, _measure);
    final cells = <String, double>{};
    for (final row in widget.rows) {
      final r = _rowsBy.of(row).$1;
      final c = _colsBy.of(row).$1;
      cells['$r|$c'] = (cells['$r|$c'] ?? 0) + _measure.of(row);
    }
    final grand = rowGroups.fold<double>(0, (s, r) => s + r.$3);
    final maxCell = cells.values.fold<double>(0, (m, v) => math.max(m, v));
    String fmt(double v) => v == 0 ? '–' : formatMeasure(_measure, v, widget.currency);
    const head = Color(0xFFE8EFFF);
    const foot = Color(0xFFF4F7FE);

    // Row labels stay put on the left; the numbers scroll sideways under one header.
    final labels = Column(
      children: [
        _cell('${_rowsBy.label} ↓ / ${_colsBy.label} →',
            width: _labelWidth, bold: true, left: true, background: head, header: true),
        for (final r in rowGroups) _cell(r.$2, width: _labelWidth, bold: true, left: true, background: Colors.white),
        _cell('Total', width: _labelWidth, bold: true, left: true, background: foot),
      ],
    );
    final numbers = Column(
      children: [
        Row(children: [
          for (final c in colGroups) _cell(c.$2, bold: true, background: head, header: true),
          _cell('Total', bold: true, background: head),
        ]),
        for (final r in rowGroups)
          Row(children: [
            for (final c in colGroups)
              _cell(
                fmt(cells['${r.$1}|${c.$1}'] ?? 0),
                background: Color.lerp(Colors.white, const Color(0xFFBFD3FF),
                    maxCell == 0 ? 0 : ((cells['${r.$1}|${c.$1}'] ?? 0) / maxCell).clamp(0.0, 1.0)),
              ),
            _cell(fmt(r.$3), bold: true, background: foot),
          ]),
        Row(children: [
          for (final c in colGroups) _cell(fmt(c.$3), bold: true, background: foot),
          _cell(fmt(grand), bold: true, background: const Color(0xFFE8EFFF), colour: AppColors.primary),
        ]),
      ],
    );
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
      children: [
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            _pickerChip(context, 'Rows: ', _rowsBy, _dims, (d) => d.label, (d) => setState(() => _rowsBy = d)),
            _pickerChip(context, 'Columns: ', _colsBy, _dims, (d) => d.label, (d) => setState(() => _colsBy = d)),
            _pickerChip(context, '', _measure, _measures, (m) => m.label, (m) => setState(() => _measure = m)),
          ],
        ),
        const SizedBox(height: 10),
        Card(
          clipBehavior: Clip.antiAlias,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              labels,
              Expanded(
                child: SingleChildScrollView(scrollDirection: Axis.horizontal, child: numbers),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ======================================================================
// Calendar
// ======================================================================
bool reportHasDates(List<Map<String, dynamic>> columns) => columns.any((c) => c['key'] == 'date');

class ReportCalendarView extends StatefulWidget {
  const ReportCalendarView({
    super.key,
    required this.reportKey,
    required this.columns,
    required this.rows,
    required this.start,
    required this.end,
    required this.format,
    this.onePerson = true,
  });

  final String reportKey;
  final List<Map<String, dynamic>> columns;
  final List<Map<String, dynamic>> rows;
  final DateTime start;
  final DateTime end;
  final bool onePerson;
  final String Function(Map<String, dynamic> column, dynamic value) format;

  @override
  State<ReportCalendarView> createState() => _ReportCalendarViewState();
}

class _ReportCalendarViewState extends State<ReportCalendarView> {
  late DateTime _month = DateTime(widget.end.year, widget.end.month, 1);
  DateTime? _picked;

  static String _key(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  @override
  void didUpdateWidget(covariant ReportCalendarView old) {
    super.didUpdateWidget(old);
    if (old.end != widget.end) _month = DateTime(widget.end.year, widget.end.month, 1);
  }

  bool get _attendance => widget.reportKey == 'attendance';

  /// Colour of a day: attendance reads its status, other reports shade by how much happened.
  (Color, Color) _tone(List<Map<String, dynamic>> rows, DateTime day, double top) {
    final today = DateTime.now();
    final future = day.isAfter(DateTime(today.year, today.month, today.day));
    if (_attendance) {
      if (rows.isEmpty) {
        if (future || day.isBefore(widget.start) || day.isAfter(widget.end)) {
          return (Colors.white, AppColors.muted);
        }
        if (day.weekday == DateTime.sunday) return (const Color(0xFFF1F3F8), AppColors.muted);
        return widget.onePerson
            ? (const Color(0xFFFDECEC), AppColors.danger)
            : (Colors.white, AppColors.muted);
      }
      final leave = rows.every((r) => r['status'] == 'On leave');
      if (leave) return (const Color(0xFFFFF4D6), const Color(0xFFB7791F));
      return (const Color(0xFFE3F6EA), AppColors.success);
    }
    if (rows.isEmpty || top == 0) return (Colors.white, AppColors.muted);
    final amount = _amount(rows);
    return (Color.lerp(const Color(0xFFEFF4FF), const Color(0xFF9DBBFF), (amount / top).clamp(0.0, 1.0))!,
        AppColors.text);
  }

  Map<String, dynamic>? get _measure =>
      widget.columns.where((c) => c['total'] == true && c['type'] == 'money').firstOrNull ??
      widget.columns.where((c) => c['total'] == true).firstOrNull;

  double _amount(List<Map<String, dynamic>> rows) {
    final m = _measure;
    if (m == null) return rows.length.toDouble();
    return rows.fold<double>(0, (s, r) => s + ((r[m['key']] as num?) ?? 0).toDouble());
  }

  String _short(List<Map<String, dynamic>> rows) {
    if (rows.isEmpty) return '';
    if (_attendance) {
      if (rows.every((r) => r['status'] == 'On leave')) return widget.onePerson ? 'Leave' : '${rows.length} off';
      final present = rows.where((r) => r['status'] != 'On leave').map((r) => r['employee']).toSet().length;
      if (!widget.onePerson) return '$present in';
      final hours = rows.fold<double>(0, (s, r) => s + ((r['hours'] as num?) ?? 0).toDouble());
      return hours == 0 ? 'In' : '${hours.toStringAsFixed(1)}h';
    }
    final m = _measure;
    final value = _amount(rows);
    if (m == null) return '${rows.length}';
    final text = widget.format(m, value);
    return text.length > 7 ? '${rows.length}' : text;
  }

  @override
  Widget build(BuildContext context) {
    final byDay = <String, List<Map<String, dynamic>>>{};
    for (final r in widget.rows) {
      byDay.putIfAbsent('${r['date']}', () => []).add(r);
    }
    final first = _month;
    final days = DateTime(first.year, first.month + 1, 0).day;
    final lead = first.weekday - 1; // Monday first
    final top = [
      for (var d = 1; d <= days; d++) _amount(byDay[_key(DateTime(first.year, first.month, d))] ?? const [])
    ].fold<double>(0, math.max);
    final picked = _picked;
    final pickedRows = picked == null ? const <Map<String, dynamic>>[] : (byDay[_key(picked)] ?? const []);
    final headline = widget.columns.firstWhere((c) => c['key'] == 'employee',
        orElse: () => widget.columns.firstWhere((c) => c['key'] == 'customer', orElse: () => widget.columns.first));

    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 6, 8, 12),
            child: Column(
              children: [
                Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.chevron_left_rounded),
                      onPressed: () => setState(() => _month = DateTime(_month.year, _month.month - 1, 1)),
                    ),
                    Expanded(
                      child: Text(
                        '${const ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'][_month.month - 1]} ${_month.year}',
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.chevron_right_rounded),
                      onPressed: () => setState(() => _month = DateTime(_month.year, _month.month + 1, 1)),
                    ),
                  ],
                ),
                Row(
                  children: [
                    for (final d in const ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'])
                      Expanded(
                        child: Center(
                          child: Text(d,
                              style: const TextStyle(
                                  fontSize: 11.5, color: AppColors.muted, fontWeight: FontWeight.w700)),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 6),
                GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 7, mainAxisSpacing: 4, crossAxisSpacing: 4, childAspectRatio: 0.82),
                  itemCount: lead + days,
                  itemBuilder: (context, i) {
                    if (i < lead) return const SizedBox.shrink();
                    final day = DateTime(first.year, first.month, i - lead + 1);
                    final rows = byDay[_key(day)] ?? const <Map<String, dynamic>>[];
                    final (background, foreground) = _tone(rows, day, top);
                    final selected = picked != null && _key(picked) == _key(day);
                    return InkWell(
                      borderRadius: BorderRadius.circular(10),
                      onTap: () => setState(() => _picked = selected ? null : day),
                      child: Container(
                        decoration: BoxDecoration(
                          color: background,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: selected ? AppColors.primary : const Color(0xFFE3E9F6),
                            width: selected ? 2 : 1,
                          ),
                        ),
                        padding: const EdgeInsets.all(3),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text('${day.day}',
                                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5)),
                            const SizedBox(height: 2),
                            FittedBox(
                              child: Text(_short(rows),
                                  style: TextStyle(
                                      fontSize: 10.5, color: foreground, fontWeight: FontWeight.w700)),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
                if (_attendance) ...[
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 14,
                    runSpacing: 4,
                    children: [
                      _legend(const Color(0xFFE3F6EA), 'Present'),
                      _legend(const Color(0xFFFFF4D6), 'Leave'),
                      if (widget.onePerson) _legend(const Color(0xFFFDECEC), 'Absent'),
                      _legend(const Color(0xFFF1F3F8), 'Sunday'),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
        if (picked != null) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 12, 4, 6),
            child: Text(
              '${picked.day}/${picked.month}/${picked.year} · ${pickedRows.length} record${pickedRows.length == 1 ? '' : 's'}',
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
          if (pickedRows.isEmpty)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Text('Nothing on this day', style: TextStyle(color: AppColors.muted)),
              ),
            ),
          for (final row in pickedRows)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(widget.format(headline, row[headline['key']]),
                        style: const TextStyle(fontWeight: FontWeight.w800)),
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 12,
                      runSpacing: 4,
                      children: [
                        for (final c in widget.columns)
                          if (c != headline && c['key'] != 'date' && row[c['key']] != null && row[c['key']] != '')
                            Text.rich(TextSpan(children: [
                              TextSpan(
                                  text: '${c['label']}: ',
                                  style: const TextStyle(color: AppColors.muted, fontSize: 12.5)),
                              TextSpan(
                                  text: widget.format(c, row[c['key']]),
                                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12.5)),
                            ])),
                      ],
                    ),
                  ],
                ),
              ),
            ),
        ],
      ],
    );
  }

  Widget _legend(Color colour, String label) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(
                color: colour,
                borderRadius: BorderRadius.circular(3),
                border: Border.all(color: const Color(0xFFD5DCEB))),
          ),
          const SizedBox(width: 5),
          Text(label, style: const TextStyle(fontSize: 12, color: AppColors.muted)),
        ],
      );
}

// ======================================================================
// Map
// ======================================================================
bool reportHasPlaces(List<Map<String, dynamic>> rows) =>
    rows.any((r) => r['_lat'] is num && r['_lng'] is num && (r['_lat'] as num) != 0);

class ReportMapView extends StatefulWidget {
  const ReportMapView({super.key, required this.columns, required this.rows, this.currency, required this.format});

  final List<Map<String, dynamic>> columns;
  final List<Map<String, dynamic>> rows;
  final String? currency;
  final String Function(Map<String, dynamic> column, dynamic value) format;

  @override
  State<ReportMapView> createState() => _ReportMapViewState();
}

class _ReportMapViewState extends State<ReportMapView> {
  Map<String, dynamic>? _selected;

  Color _colour(Map<String, dynamic> row) {
    final status = widget.columns.where((c) => c['type'] == 'status').firstOrNull;
    final text = '${status == null ? '' : row[status['key']] ?? ''}'.toLowerCase();
    if (text.contains('offsite') || text.contains('cancel') || text.contains('reject')) return AppColors.danger;
    if (text.contains('onsite') || text.contains('received') || text.contains('approved')) return AppColors.success;
    if (text.isEmpty) return AppColors.primary;
    return AppColors.warning;
  }

  @override
  Widget build(BuildContext context) {
    final placed = widget.rows.where((r) => r['_lat'] is num && r['_lng'] is num && (r['_lat'] as num) != 0).toList();
    final points = [for (final r in placed) LatLng((r['_lat'] as num).toDouble(), (r['_lng'] as num).toDouble())];
    final selected = _selected;
    final headline = widget.columns.firstWhere((c) => c['key'] == 'customer',
        orElse: () => widget.columns.firstWhere((c) => c['key'] == 'employee', orElse: () => widget.columns.first));
    return Stack(
      children: [
        AppMap(
          fitPoints: points,
          center: points.isNotEmpty ? points.first : null,
          children: [
            MarkerLayer(markers: [
              for (var i = 0; i < placed.length; i++)
                Marker(
                  point: points[i],
                  width: MapPin.size.width,
                  height: MapPin.size.height,
                  alignment: Alignment.topCenter,
                  child: GestureDetector(
                    onTap: () => setState(() => _selected = placed[i]),
                    child: MapPin(color: _colour(placed[i]), selected: identical(placed[i], selected)),
                  ),
                ),
            ]),
          ],
        ),
        Positioned(
          left: 12,
          top: 12,
          child: Chip(
            avatar: const Icon(Icons.place_rounded, size: 16, color: AppColors.primary),
            label: Text('${placed.length} of ${widget.rows.length} on the map'),
          ),
        ),
        if (selected != null)
          Positioned(
            left: 12,
            right: 12,
            bottom: 24,
            child: Card(
              elevation: 6,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 10, 6, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(widget.format(headline, selected[headline['key']]),
                              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                        ),
                        IconButton(
                            onPressed: () => setState(() => _selected = null), icon: const Icon(Icons.close_rounded)),
                      ],
                    ),
                    Wrap(
                      spacing: 12,
                      runSpacing: 4,
                      children: [
                        for (final c in widget.columns)
                          if (c != headline && selected[c['key']] != null && selected[c['key']] != '')
                            Text.rich(TextSpan(children: [
                              TextSpan(text: '${c['label']}: ', style: const TextStyle(color: AppColors.muted, fontSize: 12.5)),
                              TextSpan(
                                  text: widget.format(c, selected[c['key']]),
                                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12.5)),
                            ])),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}
