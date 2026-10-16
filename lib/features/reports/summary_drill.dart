import 'dart:io';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/format.dart';
import '../../core/services.dart';
import '../../core/theme.dart';
import '../../widgets/common.dart';
import '../../core/manager_ui.dart';
import '../../widgets/skeleton.dart';
import '../team/my_team_screen.dart' show ManagerEmployeeReportScreen;
import '../team/employee_report_pages.dart' as lead show EmployeeTasksScreen;
import 'employee_report_pages.dart';

/// Look of one figure: icon and colour by what it counts.
(IconData, Color) metricLook(String key) => switch (key) {
      'days' || 'present' => (Icons.event_available_rounded, AppColors.success),
      'hours' => (Icons.schedule_rounded, AppColors.purple),
      'late' => (Icons.error_rounded, AppColors.danger),
      'visits' => (Icons.location_on_rounded, AppColors.primary),
      'offsite' => (Icons.near_me_rounded, AppColors.purple),
      'orders' || 'count' || 'units' => (Icons.assignment_rounded, AppColors.warning),
      'sales' || 'amount' => (Icons.bar_chart_rounded, AppColors.primary),
      'collections' || 'collected' => (Icons.currency_rupee_rounded, AppColors.success),
      'expenses' => (Icons.account_balance_wallet_rounded, AppColors.danger),
      'customers' => (Icons.groups_rounded, AppColors.primary),
      'km' || 'distance' => (Icons.add_road_rounded, AppColors.muted),
      'difference' || 'missed' => (Icons.pending_actions_rounded, AppColors.danger),
      'quantity' => (Icons.inventory_2_rounded, AppColors.warning),
      'outlets' => (Icons.storefront_rounded, AppColors.primary),
      'planned' => (Icons.event_note_rounded, AppColors.primary),
      'visited' => (Icons.task_alt_rounded, AppColors.success),
      'last_visit' => (Icons.history_rounded, AppColors.purple),
      'check_in' || 'check_out' || 'time' || 'first' || 'last' || 'minutes' => (Icons.schedule_rounded, AppColors.purple),
      'mode' || 'cash' || 'online' || 'cheque' || 'pending' => (Icons.payments_rounded, AppColors.success),
      'category' || 'type' || 'band' || 'visit_type' => (Icons.label_rounded, AppColors.warning),
      'route' || 'city' => (Icons.route_rounded, AppColors.primary),
      'number' || 'reference' || 'sku' => (Icons.tag_rounded, AppColors.muted),
      'distributor' => (Icons.local_shipping_rounded, AppColors.purple),
      'outcome' || 'note' => (Icons.notes_rounded, AppColors.muted),
      'approved' => (Icons.verified_rounded, AppColors.success),
      'waiting' => (Icons.hourglass_top_rounded, AppColors.warning),
      'score' || 'rank' || 'share' || 'completion' => (Icons.emoji_events_rounded, AppColors.warning),
      'phone' => (Icons.call_rounded, AppColors.success),
      'date' || 'date_to' || 'days' => (Icons.event_rounded, AppColors.primary),
      _ => (Icons.insights_rounded, AppColors.primary),
    };

String _money(num? v, String? currency) => fmtMoney(v ?? 0, currency);

String _day(String iso) {
  final d = DateTime.tryParse(iso);
  if (d == null) return iso;
  const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  return '${d.day} ${months[d.month - 1]} ${d.year}';
}

String _weekday(String iso) {
  final d = DateTime.tryParse(iso);
  if (d == null) return '';
  return const ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'][d.weekday - 1];
}

/// A soft coloured tile: icon, label and value (the top strip of each screen).
class MetricTile extends StatelessWidget {
  const MetricTile(
      {super.key, required this.metric, required this.label, required this.value, this.big = false, this.plain = false});

  /// Label and value only, on a white tile (reports other than the summary).
  final bool plain;

  final String metric;
  final String label;
  final String value;
  final bool big;

  @override
  Widget build(BuildContext context) {
    final (icon, colour) = metricLook(metric);
    if (plain) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(label,
                maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11.5, color: AppColors.muted)),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(value, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.text)),
            ),
          ],
        ),
      );
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: BoxDecoration(
        color: colour.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(color: colour.withValues(alpha: 0.14), shape: BoxShape.circle),
            child: Icon(icon, color: colour, size: 18),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11, color: AppColors.muted)),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(value,
                      style: TextStyle(fontSize: big ? 17 : 15, fontWeight: FontWeight.w800, color: AppColors.text)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Small figure inside a summary card: icon in a soft circle, value over caption.
class _Mini extends StatelessWidget {
  const _Mini(this.metric, this.value, this.caption);

  final String metric;
  final String value;
  final String caption;

  @override
  Widget build(BuildContext context) {
    final (icon, colour) = metricLook(metric);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(color: colour.withValues(alpha: 0.12), shape: BoxShape.circle),
            child: Icon(icon, color: colour, size: 18),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(value, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
                ),
                Text(caption,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 11, color: AppColors.muted)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Label over value, left aligned, no icon (plain report cards).
class _Plain extends StatelessWidget {
  const _Plain(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 280),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 11.5, color: AppColors.muted)),
          const SizedBox(height: 2),
          Text(value,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5, color: AppColors.text)),
        ],
      ),
    );
  }
}

/// One line of the summary (a person, a day, or everyone): header and ten figures.
class EmployeeSummaryCard extends StatelessWidget {
  const EmployeeSummaryCard({
    super.key,
    required this.row,
    required this.currency,
    required this.saleWord,
    this.onTap,
    this.highlight = false,
    this.subtitle,
    this.badge,
    this.figures,
    this.value,
    this.valueCaption = 'Total value',
    this.status,
    this.statusColour,
    this.plain = false,
  });

  /// Reports other than the summary: no badge, no icons - label over value only.
  final bool plain;

  /// A small coloured pill under the headline value (e.g. Approved, On duty).
  final String? status;
  final Color? statusColour;

  /// (metric, value, caption) shown under the header, three to a row.
  /// Default: visits, offsite, demand, collected, expenses, new customers.
  final List<(String, String, String)>? figures;

  /// Headline on the right (default: the sales value).
  final String? value;
  final String valueCaption;

  final Map<String, dynamic> row;
  final String? currency;
  final String saleWord;
  final VoidCallback? onTap;
  final bool highlight;
  final String? subtitle;

  /// Text in the round badge (defaults to the name's initials).
  final String? badge;

  static const _tints = [
    AppColors.primary,
    AppColors.purple,
    Color(0xFFEA7A1A),
    AppColors.success,
    Color(0xFF0D9488),
  ];

  @override
  Widget build(BuildContext context) {
    final name = '${row['employee'] ?? ''}';
    final initials = badge ??
        name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).take(2).map((p) => p[0]).join().toUpperCase();
    final tint = _tints[name.hashCode.abs() % _tints.length];
    String n(String k) => '${(row[k] as num?)?.toInt() ?? 0}';
    final shown = figures ??
        [
          ('visits', n('visits'), 'Visits'),
          ('offsite', n('offsite'), 'Offsite'),
          ('orders', n('orders'), saleWord),
          ('collections', _money(row['collections'] as num?, currency), 'Collected'),
          ('expenses', _money(row['expenses'] as num?, currency), 'Expenses'),
          ('customers', n('customers'), 'New customers'),
        ];
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: highlight ? AppColors.primary : AppColors.border, width: highlight ? 1.5 : 1),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 14, 12, 10),
          child: Column(
            children: [
              Row(
                children: [
                  if (!plain) ...[
                    CircleAvatar(
                      radius: 26,
                      backgroundColor: tint.withValues(alpha: 0.12),
                      child: Text(initials,
                          style: TextStyle(color: tint, fontWeight: FontWeight.w800, fontSize: 17)),
                    ),
                    const SizedBox(width: 12),
                  ],
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16.5)),
                        if (subtitle != null)
                          Text(subtitle!, style: const TextStyle(color: AppColors.muted, fontSize: 12.5)),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(value ?? _money(row['sales'] as num?, currency),
                          style: const TextStyle(
                              fontWeight: FontWeight.w900, fontSize: 16.5, color: AppColors.primary)),
                      if (valueCaption.isNotEmpty)
                        Text(valueCaption, style: const TextStyle(color: AppColors.muted, fontSize: 12)),
                      if (status != null && status!.isNotEmpty)
                        Container(
                          margin: const EdgeInsets.only(top: 4),
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                          decoration: BoxDecoration(
                            color: (statusColour ?? AppColors.primary).withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(status!,
                              style: TextStyle(
                                  color: statusColour ?? AppColors.primary,
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w700)),
                        ),
                    ],
                  ),
                  if (onTap != null) const Icon(Icons.chevron_right_rounded, color: AppColors.muted),
                ],
              ),
              if (plain && shown.isNotEmpty) const Divider(height: 20, color: AppColors.border),
              if (!plain) const SizedBox(height: 12),
              // Plain cards flow freely: each figure takes the width its text needs.
              if (plain)
                Align(
                  alignment: Alignment.centerLeft,
                  child: Wrap(
                    spacing: 28,
                    runSpacing: 10,
                    children: [for (final f in shown) _Plain(f.$3, f.$2)],
                  ),
                ),
              for (var r = 0; !plain && r < shown.length; r += 3)
                _row([
                  for (final f in shown.skip(r).take(3))
                    plain ? _Plain(f.$3, f.$2) : _Mini(f.$1, f.$2, f.$3),
                  // Short last row keeps the column widths of the rows above.
                  for (var k = shown.skip(r).take(3).length; k < 3; k++) const SizedBox(),
                ]),
            ],
          ),
        ),
      ),
    );
  }

  /// Equal columns with thin dividers between them, all rows the same height.
  Widget _row(List<Widget> items) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < items.length; i++) ...[
              if (i > 0) const VerticalDivider(width: 1, thickness: 1, color: AppColors.border),
              Expanded(child: Align(alignment: plain ? Alignment.centerLeft : Alignment.center, child: items[i])),
            ],
          ],
        ),
      ),
    );
  }
}

// ======================================================================
// Employee report: overview, daily breakdown, visits, demands
// ======================================================================
class EmployeeReportScreen extends StatefulWidget {
  const EmployeeReportScreen({
    super.key,
    required this.memberId,
    required this.name,
    required this.start,
    required this.end,
  });

  final String memberId;
  final String name;
  final DateTime start;
  final DateTime end;

  @override
  State<EmployeeReportScreen> createState() => _EmployeeReportScreenState();
}

class _EmployeeReportScreenState extends State<EmployeeReportScreen> {
  late DateTime _start = widget.start;
  late DateTime _end = widget.end;
  String _period = 'custom';
  Map<String, dynamic>? _overall;
  List<Map<String, dynamic>> _days = [];
  List<Map<String, dynamic>> _visits = [];
  List<Map<String, dynamic>> _orders = [];
  List<Map<String, dynamic>> _lateRows = [];
  List<Map<String, dynamic>> _taskRows = [];
  List<String> _territories = [];
  List<String> _routes = [];
  String? _currency;
  String? _error;
  bool _loading = true;
  bool _downloading = false;

  @override
  void initState() {
    super.initState();
    for (final p in ['today', 'week', 'month']) {
      final r = _rangeOf(p);
      if (DateUtils.isSameDay(r.start, _start) && DateUtils.isSameDay(r.end, _end)) _period = p;
    }
    _load();
  }

  DateTimeRange _rangeOf(String period) {
    final today = DateUtils.dateOnly(DateTime.now());
    return switch (period) {
      'today' => DateTimeRange(start: today, end: today),
      'week' => DateTimeRange(start: today.subtract(Duration(days: today.weekday - 1)), end: today),
      _ => DateTimeRange(start: DateTime(today.year, today.month, 1), end: today),
    };
  }

  void _choosePeriod(String period) {
    final r = _rangeOf(period);
    setState(() {
      _period = period;
      _start = r.start;
      _end = r.end;
    });
    _load();
  }

  Future<void> _pickDates() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime.now().subtract(const Duration(days: 730)),
      lastDate: DateTime.now(),
      initialDateRange: DateTimeRange(start: _start, end: _end),
    );
    if (picked == null) return;
    setState(() {
      _period = 'custom';
      _start = picked.start;
      _end = picked.end;
    });
    _load();
  }

  static List<Map<String, dynamic>> _rowsOf(Object? v) => ((v as List?) ?? []).cast<Map<String, dynamic>>();

  static List<String> _namesOf(Object? v) => [
        for (final e in (v as List?) ?? [])
          if (e is Map ? e['name'] != null : '$e'.isNotEmpty) e is Map ? '${e['name']}' : '$e',
      ];

  /// One call gives the whole report: the figures, the lists behind them, and the territories and routes worked.
  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final r = await Services.api.get('/api/v1/team/employee-report', query: {
        'member': int.tryParse(widget.memberId) ?? widget.memberId,
        'start': fmtDate(_start),
        'end': fmtDate(_end),
      }) as Map<String, dynamic>;
      if (!mounted) return;
      final details = (r['details'] as Map?)?.cast<String, dynamic>() ?? const {};
      final visits = (r['visits'] as Map?)?.cast<String, dynamic>() ?? const {};
      final tasks = (r['tasks'] as Map?)?.cast<String, dynamic>() ?? const {};
      setState(() {
        _overall = {
          'days': r['days_worked'],
          'late': r['late_days'],
          'km': r['distance_km'],
          'hours': r['hours'],
          'visits': visits['done'],
          'planned': visits['planned'],
          'tasks_done': tasks['done'],
          'tasks': tasks['total'],
          'bottles': r['bottles'],
          'outlets_onboarded': r['outlets'],
          'pos': r['pos_to_distributor'],
          'leads': r['new_leads'],
          'expenses': r['expenses'],
        };
        _currency = r['currency'] as String?;
        _days = [
          for (final d in _rowsOf(details['days']))
            {...d, 'days': 1, 'check_in': d['in_at'], 'check_out': d['out_at']},
        ];
        _lateRows = [
          for (final d in _rowsOf(details['late'])) {...d, 'late': 1, 'check_in': d['in_at'] ?? d['check_in']},
        ];
        _visits = [
          for (final v in _rowsOf(details['visits']))
            {
              ...v,
              'customer': (v['outlet'] as Map?)?['name'] ?? v['customer'],
              'status': v['done'] == true ? 'visited' : 'pending',
            },
        ];
        _taskRows = _rowsOf(details['tasks']);
        _orders = const [];
        _territories = _namesOf(r['territories']);
        _routes = _namesOf(r['routes']);
      });
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // ---------------------------------------------------------------- territory and route
  static String? _nameOf(Object? v) {
    if (v is Map) return v['name'] == null ? null : '${v['name']}';
    if (v is String && v.trim().isNotEmpty) return v.trim();
    return null;
  }

  /// Territory or route name -> the dates it was worked (and, for a route, its territory). The names come from the
  /// server's lists; dates are added where the day rows say which route or territory each day was.
  Map<String, ({Set<String> dates, String? territory})> _groups(String key) {
    final out = <String, ({Set<String> dates, String? territory})>{
      for (final n in key == 'route' ? _routes : _territories) n: (dates: <String>{}, territory: null),
    };
    for (final row in [..._days, ..._visits]) {
      final name = _nameOf(row[key]);
      final date = row['date'] == null ? null : '${row['date']}';
      if (name == null) continue;
      final cur = out[name] ?? (dates: <String>{}, territory: _nameOf(row['territory']));
      if (date != null) cur.dates.add(date);
      out[name] = (dates: cur.dates, territory: cur.territory ?? _nameOf(row['territory']));
    }
    return out;
  }

  String _dates(Set<String> iso) {
    final days = iso.map(DateTime.tryParse).whereType<DateTime>().toList()..sort();
    if (days.isEmpty) return '';
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${days.map((d) => d.day.toString().padLeft(2, '0')).join(', ')} ${months[days.last.month - 1]}';
  }

  String get _rangeText => '${_day(fmtDate(_start))} to ${_day(fmtDate(_end))}';

  void _groupSheet(String title, Map<String, ({Set<String> dates, String? territory})> groups, {required bool route}) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.7),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('$title – $_rangeText', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
                Text('${groups.length} ${route ? 'routes' : 'territories'} in the selected dates',
                    style: const TextStyle(fontSize: 12, color: AppColors.muted)),
              ]),
            ),
            Flexible(
              child: ListView(shrinkWrap: true, padding: const EdgeInsets.fromLTRB(12, 0, 12, 16), children: [
                for (final e in groups.entries)
                  ListTile(
                    leading: CircleAvatar(
                        backgroundColor: AppColors.primary.withValues(alpha: 0.1),
                        child: const Icon(Icons.event_note_rounded, color: AppColors.primary, size: 20)),
                    title: Text(e.key, style: const TextStyle(fontWeight: FontWeight.w800)),
                    subtitle: Text([_dates(e.value.dates), if (route && e.value.territory != null) 'Territory ${e.value.territory}'].where((s) => s.isNotEmpty).join(' · '),
                        style: const TextStyle(fontSize: 12)),
                  ),
              ]),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _placeCell(String label, String key, {required bool route}) {
    final groups = _groups(key);
    if (groups.isEmpty) return const SizedBox.shrink();
    final extra = groups.length - 1;
    return Expanded(
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: const TextStyle(fontSize: 10.5, color: AppColors.muted)),
            Text(groups.keys.first, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
          ]),
        ),
        if (extra > 0)
          InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: () => _groupSheet(route ? 'Route' : 'Territory', groups, route: route),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(color: AppColors.primary.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.warning)),
              child: Text('+$extra', style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, color: AppColors.primary)),
            ),
          ),
        const SizedBox(width: 8),
      ]),
    );
  }

  // ---------------------------------------------------------------- work buttons and boxes
  num _n(Object? v) => (v as num?) ?? 0;

  String get _rangeLabel => '${_day(fmtDate(_start))} – ${_day(fmtDate(_end))}';

  void _push(Widget screen) => Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));

  Widget _workButton(IconData icon, Color c, String value, String label, VoidCallback onTap) => Expanded(
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 3),
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
            decoration: BoxDecoration(color: c.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(16), border: Border.all(color: c.withValues(alpha: 0.5))),
            child: Column(children: [
              Icon(icon, color: c, size: 20),
              const SizedBox(height: 6),
              FittedBox(child: Text(value, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15))),
              Text('$label ›', maxLines: 1, style: const TextStyle(fontSize: 10, color: AppColors.muted)),
            ]),
          ),
        ),
      );

  Widget _box(IconData icon, Color c, String label, String value, {VoidCallback? onTap}) => InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: c.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(16)),
          child: Row(children: [
            CircleAvatar(radius: 17, backgroundColor: Colors.white, child: Icon(icon, color: c, size: 18)),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 10.5, color: AppColors.muted)),
                Text('$value${onTap == null ? '' : ' ›'}', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14.5)),
              ]),
            ),
          ]),
        ),
      );

  Widget _grid(List<Widget> tiles) => Column(children: [
        for (var i = 0; i < tiles.length; i += 2)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(children: [
              Expanded(child: tiles[i]),
              const SizedBox(width: 8),
              Expanded(child: i + 1 < tiles.length ? tiles[i + 1] : const SizedBox()),
            ]),
          ),
      ]);

  void _visitsPage() => _push(EmployeeVisitsScreen(name: widget.name, rangeText: _rangeLabel, visits: _visits, orders: _orders));

  void _tasksPage() {
    final o = _overall ?? const {};
    _push(lead.EmployeeTasksScreen(
      name: widget.name,
      rangeText: _rangeLabel,
      tasks: _taskRows,
      visitsDone: _n(o['visits']),
      visitsTotal: _n(o['planned'] ?? o['visits']),
    ));
  }

  // ---------------------------------------------------------------- download
  Future<String?> _chooseSheet(String title, String subtitle, List<(IconData, Color, String, String, String)> options) {
    return showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 17)),
                Text(subtitle, style: const TextStyle(fontSize: 12, color: AppColors.muted)),
              ]),
            ),
            for (final (icon, colour, key, label, sub) in options)
              ListTile(
                leading: CircleAvatar(backgroundColor: colour.withValues(alpha: 0.12), child: Icon(icon, color: colour)),
                title: Text(label, style: const TextStyle(fontWeight: FontWeight.w800)),
                subtitle: Text(sub, style: const TextStyle(fontSize: 12)),
                onTap: () => Navigator.pop(ctx, key),
              ),
          ]),
        ),
      ),
    );
  }

  Future<void> _download() async {
    final format = await _chooseSheet('Download report', '${widget.name.toUpperCase()} · $_rangeLabel', [
      (Icons.grid_on_rounded, AppColors.success, 'excel', 'Excel', 'All boxes and details'),
      (Icons.picture_as_pdf_rounded, AppColors.danger, 'pdf', 'PDF', 'Same report as a PDF'),
    ]);
    if (format == null || !mounted) return;
    setState(() => _downloading = true);
    File? file;
    try {
      // The server prepares the file and answers with where to fetch it.
      final r = await Services.api.post('/api/v1/team/employee-report/export', {
        'member': int.tryParse(widget.memberId) ?? widget.memberId,
        'start': fmtDate(_start),
        'end': fmtDate(_end),
        'format': format,
      }) as Map<String, dynamic>;
      final url = Uri.parse(await Services.api.url('${r['path']}'));
      final response = await http.get(url, headers: await Services.api.authHeaders());
      if (response.statusCode != 200) {
        // Not fetchable from here: let the phone's browser open the link instead.
        final opened = await launchUrl(url, mode: LaunchMode.externalApplication);
        if (!opened) throw Exception('The report could not be downloaded (${response.statusCode}).');
        return;
      }
      final dir = await getTemporaryDirectory();
      final safe = widget.name.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
      file = File('${dir.path}/Employee_Report_$safe.${format == 'excel' ? 'xlsx' : 'pdf'}');
      await file.writeAsBytes(response.bodyBytes);
    } catch (e) {
      if (mounted) showProblem(context, e.toString());
    } finally {
      if (mounted) setState(() => _downloading = false);
    }
    if (file == null || !mounted) return;
    final mime = format == 'pdf' ? 'application/pdf' : 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
    final sendTo = await _chooseSheet('Send to', 'Choose a contact', [
      (Icons.send_rounded, AppColors.success, 'share', 'WhatsApp', 'Share the file'),
      (Icons.download_rounded, AppColors.primary, 'save', 'Save to phone', 'Downloads folder'),
    ]);
    if (sendTo == null || !mounted) return;
    try {
      if (sendTo == 'save' && Platform.isAndroid) {
        final target = File('/storage/emulated/0/Download/${file.uri.pathSegments.last}');
        await file.copy(target.path);
        if (mounted) showSnack(context, 'Saved to Downloads');
        return;
      }
      await SharePlus.instance.share(ShareParams(
        files: [XFile(file.path, mimeType: mime)],
        subject: 'Employee report ${widget.name}',
      ));
    } catch (e) {
      if (mounted) showProblem(context, e.toString());
    }
  }

  // ---------------------------------------------------------------- build
  @override
  Widget build(BuildContext context) {
    if (kUseLeadManagerUi) {
      return ManagerEmployeeReportScreen(
        memberId: int.tryParse(widget.memberId) ?? 0,
        name: widget.name,
        start: widget.start,
        end: widget.end,
      );
    }
    final name = widget.name;
    final initials = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).take(2).map((p) => p[0]).join().toUpperCase();
    final o = _overall ?? const {};
    final hasPlaces = _groups('territory').isNotEmpty || _groups('route').isNotEmpty;
    final planned = o['planned'];
    return Scaffold(
      appBar: AppBar(title: const Text('Employee report', style: TextStyle(fontWeight: FontWeight.w900))),
      body: _error != null
          ? ErrorView(message: _error!, onRetry: _load)
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
                children: [
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Row(children: [
                        CircleAvatar(
                          radius: 22,
                          backgroundColor: AppColors.primary.withValues(alpha: 0.1),
                          child: Text(initials, style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.w800, fontSize: 15)),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(name.toUpperCase(), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15)),
                            Text('${_day(fmtDate(_start))} – ${_day(fmtDate(_end))}', style: const TextStyle(color: AppColors.muted, fontSize: 11.5)),
                          ]),
                        ),
                        IconButton(onPressed: _pickDates, icon: const Icon(Icons.calendar_month_rounded, color: AppColors.primary)),
                        DropdownButton<String>(
                          value: _period,
                          underline: const SizedBox.shrink(),
                          style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: AppColors.primary),
                          items: const [
                            DropdownMenuItem(value: 'today', child: Text('Today')),
                            DropdownMenuItem(value: 'week', child: Text('This week')),
                            DropdownMenuItem(value: 'month', child: Text('This month')),
                            DropdownMenuItem(value: 'custom', child: Text('Custom')),
                          ],
                          onChanged: (v) {
                            if (v == null) return;
                            v == 'custom' ? _pickDates() : _choosePeriod(v);
                          },
                        ),
                      ]),
                    ),
                  ),
                  if (hasPlaces)
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(14, 10, 6, 10),
                        child: Row(children: [
                          _placeCell('Territory', 'territory', route: false),
                          _placeCell('Route', 'route', route: true),
                        ]),
                      ),
                    ),
                  const SizedBox(height: 4),
                  if (_loading && _overall == null)
                    const Padding(padding: EdgeInsets.all(40), child: LoadingView())
                  else ...[
                    Row(children: [
                      _workButton(Icons.event_available_rounded, AppColors.success, '${_n(o['days'])}', 'Days worked',
                          () => _push(DaysTableScreen(title: 'Days worked', name: widget.name, rangeText: _rangeLabel, days: _days.where((d) => _n(d['days']) > 0 || _n(d['visits']) > 0).toList()))),
                      _workButton(Icons.schedule_rounded, AppColors.danger, '${_n(o['late'])}', 'Late days',
                          () => _push(LateDaysScreen(name: widget.name, rangeText: _rangeLabel, days: _lateRows, memberId: widget.memberId))),
                      _workButton(Icons.add_road_rounded, AppColors.primary, '${_n(o['km']).toStringAsFixed(0)} km', 'Distance',
                          () => _push(DaysTableScreen(title: 'Distance', name: widget.name, rangeText: _rangeLabel, days: _days.where((d) => _n(d['km']) > 0).toList(), sortBy: 'km'))),
                      _workButton(Icons.timer_rounded, AppColors.purple, fmtHours(o['hours'] as num?), 'Hours',
                          () => _push(DaysTableScreen(title: 'Hours', name: widget.name, rangeText: _rangeLabel, days: _days.where((d) => _n(d['hours']) > 0).toList(), sortBy: 'hours'))),
                    ]),
                    const SizedBox(height: 12),
                    _grid([
                      _box(Icons.location_on_rounded, AppColors.primary, 'Visits', planned == null ? '${_n(o['visits'])}' : '${_n(o['visits'])} / ${_n(planned)}', onTap: _visitsPage),
                      _box(Icons.task_alt_rounded, AppColors.success, 'Tasks', '${_n(o['tasks_done'])} / ${_n(o['tasks'])}', onTap: _tasksPage),
                      _box(Icons.local_drink_rounded, AppColors.primary, 'Bottles sold', '${_n(o['bottles'])}'),
                      _box(Icons.storefront_rounded, AppColors.success, 'Onboarded outlets', '${_n(o['outlets_onboarded'] ?? o['customers'])}'),
                      _box(Icons.shopping_cart_rounded, AppColors.warning, 'POs to distributor', '${_n(o['pos'] ?? o['orders'])}'),
                      _box(Icons.person_add_alt_1_rounded, AppColors.sky, 'New leads', '${_n(o['leads'])}'),
                      _box(Icons.receipt_long_rounded, AppColors.danger, 'Expenses', _money(o['expenses'] as num?, _currency)),
                    ]),
                    const SizedBox(height: 8),
                    GradientButton(label: 'Download report (Excel / PDF)', icon: Icons.download_rounded, busy: _downloading, onPressed: _download),
                  ],
                ],
              ),
            ),
    );
  }
}

Widget _pair(String label, String value) => Text.rich(TextSpan(children: [
      TextSpan(text: '$label  ', style: const TextStyle(color: AppColors.muted, fontSize: 12.5)),
      TextSpan(text: value, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5)),
    ]));

/// One customer visit: name, time, onsite/offsite, and what was ordered there.
class VisitCard extends StatelessWidget {
  const VisitCard({super.key, required this.visit, this.orderValue, this.currency, this.showDate = false});

  final Map<String, dynamic> visit;
  final double? orderValue;
  final String? currency;
  final bool showDate;

  @override
  Widget build(BuildContext context) {
    final offsite = '${visit['visit_type'] ?? ''}'.toLowerCase().contains('off');
    final colour = offsite ? AppColors.purple : AppColors.success;
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(color: colour.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12)),
              child: Icon(offsite ? Icons.storefront_rounded : Icons.apartment_rounded, color: colour),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text('${visit['customer'] ?? ''}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                      ),
                      Text(
                        [if (showDate) _day('${visit['date']}'), '${visit['check_in'] ?? ''}'].join(' · '),
                        style: const TextStyle(color: AppColors.muted, fontSize: 12),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          [
                            if (visit['check_out'] != null) 'Out ${visit['check_out']}',
                            if ((visit['minutes'] ?? 0) != 0) '${visit['minutes']} min',
                            if ('${visit['outcome'] ?? ''}'.isNotEmpty) '${visit['outcome']}',
                          ].join(' · '),
                          style: const TextStyle(color: AppColors.muted, fontSize: 12.5),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                        decoration:
                            BoxDecoration(color: colour.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)),
                        child: Text(offsite ? 'Offsite' : 'Visited',
                            style: TextStyle(color: colour, fontSize: 12, fontWeight: FontWeight.w700)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  orderValue == null
                      ? const Text('No order', style: TextStyle(color: AppColors.muted, fontSize: 12.5))
                      : _pair('Order value', _money(orderValue, currency)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ======================================================================
// Visit details: one person, one day
// ======================================================================
class VisitDetailsScreen extends StatefulWidget {
  const VisitDetailsScreen({
    super.key,
    required this.memberId,
    required this.name,
    required this.date,
    this.days = const [],
  });

  final String memberId;
  final String name;
  final DateTime date;

  /// Days of the period, newest first, for the previous / next arrows.
  final List<String> days;

  @override
  State<VisitDetailsScreen> createState() => _VisitDetailsScreenState();
}

class _VisitDetailsScreenState extends State<VisitDetailsScreen> {
  late DateTime _date = widget.date;
  Map<String, dynamic> _figures = {};
  List<Map<String, dynamic>> _visits = [];
  List<Map<String, dynamic>> _orders = [];
  String? _currency;
  String? _error;
  bool _loading = true;
  String _filter = 'all';
  String _find = '';

  bool get _demandFlow => Services.auth.profile?.isDemandFlow ?? false;

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
    final day = fmtDate(_date);
    final query = {'start': day, 'end': day, 'member': widget.memberId};
    try {
      final results = await Future.wait([
        Services.api.get('/api/v1/reports/summary', query: {...query, 'by': 'overall'}),
        Services.api.get('/api/v1/reports/visits', query: query),
        Services.api.get('/api/v1/reports/${_demandFlow ? 'demands' : 'orders'}', query: query),
      ]);
      List<Map<String, dynamic>> rows(Object? r) => (((r as Map)['rows'] as List?) ?? []).cast<Map<String, dynamic>>();
      if (!mounted || fmtDate(_date) != day) return;
      setState(() {
        final o = rows(results[0]);
        _figures = o.isEmpty ? {} : o.first;
        _visits = rows(results[1])..sort((a, b) => '${a['check_in']}'.compareTo('${b['check_in']}'));
        _orders = rows(results[2]);
        _currency = (results[0] as Map)['currency'] as String?;
      });
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _shift(int days) {
    setState(() => _date = _date.add(Duration(days: days)));
    _load();
  }

  double? _orderValue(Map<String, dynamic> visit) {
    final same = _orders.where((o) => o['customer'] == visit['customer']);
    if (same.isEmpty) return null;
    return same.fold<double>(0, (s, o) => s + ((o['amount'] as num?) ?? 0).toDouble());
  }

  @override
  Widget build(BuildContext context) {
    final iso = fmtDate(_date);
    final offsite = _visits.where((v) => '${v['visit_type']}'.toLowerCase().contains('off')).length;
    final shown = _visits.where((v) {
      final off = '${v['visit_type']}'.toLowerCase().contains('off');
      if (_filter == 'visited' && off) return false;
      if (_filter == 'offsite' && !off) return false;
      return _find.isEmpty || '${v['customer']}'.toLowerCase().contains(_find.toLowerCase());
    }).toList();
    final f = _figures;
    final today = DateTime.now();
    final isFuture = !_date.isBefore(DateTime(today.year, today.month, today.day));
    return Scaffold(
      appBar: AppBar(title: Text('Visit details · ${widget.name}')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 10, 6, 10),
                child: Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                          color: AppColors.primary.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(12)),
                      child: const Icon(Icons.event_note_rounded, color: AppColors.primary),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(_day(iso), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
                          Text(_weekday(iso), style: const TextStyle(color: AppColors.muted)),
                        ],
                      ),
                    ),
                    IconButton(onPressed: () => _shift(-1), icon: const Icon(Icons.chevron_left_rounded)),
                    IconButton(
                        onPressed: isFuture ? null : () => _shift(1), icon: const Icon(Icons.chevron_right_rounded)),
                  ],
                ),
              ),
            ),
            if (_loading) const LinearProgressIndicator(minHeight: 2),
            if (_error != null) ErrorView(message: _error!, onRetry: _load),
            const SizedBox(height: 8),
            _pairTiles([
              MetricTile(metric: 'visits', label: 'Visits', value: '${f['visits'] ?? _visits.length}'),
              MetricTile(
                  metric: 'orders', label: _demandFlow ? 'Demand' : 'Orders', value: '${f['orders'] ?? _orders.length}'),
              MetricTile(metric: 'collections', label: 'Collected', value: _money(f['collections'] as num?, _currency)),
              MetricTile(metric: 'expenses', label: 'Expenses', value: _money(f['expenses'] as num?, _currency)),
              MetricTile(metric: 'km', label: 'Distance', value: '${((f['km'] as num?) ?? 0).toStringAsFixed(1)} km'),
              MetricTile(metric: 'customers', label: 'New customers', value: '${f['customers'] ?? 0}'),
            ]),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              children: [
                for (final (key, label) in [
                  ('all', 'All (${_visits.length})'),
                  ('visited', 'Visited (${_visits.length - offsite})'),
                  ('offsite', 'Offsite ($offsite)'),
                ])
                  ChoiceChip(
                    label: Text(label),
                    selected: _filter == key,
                    showCheckmark: false,
                    selectedColor: AppColors.primary,
                    labelStyle:
                        TextStyle(color: _filter == key ? Colors.white : AppColors.text, fontWeight: FontWeight.w700),
                    onSelected: (_) => setState(() => _filter = key),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            TextField(
              onChanged: (v) => setState(() => _find = v),
              decoration: const InputDecoration(
                hintText: 'Search customer',
                suffixIcon: Icon(Icons.search_rounded),
                isDense: true,
              ),
            ),
            const SizedBox(height: 8),
            if (!_loading && shown.isEmpty)
              const Card(child: Padding(padding: EdgeInsets.all(20), child: Text('No visits on this day'))),
            for (final v in shown) VisitCard(visit: v, orderValue: _orderValue(v), currency: _currency),
          ],
        ),
      ),
    );
  }

  Widget _pairTiles(List<Widget> tiles) => Column(
        children: [
          for (var i = 0; i < tiles.length; i += 2)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(children: [
                Expanded(child: tiles[i]),
                const SizedBox(width: 8),
                Expanded(child: i + 1 < tiles.length ? tiles[i + 1] : const SizedBox()),
              ]),
            ),
        ],
      );
}
