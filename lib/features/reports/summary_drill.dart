import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../core/services.dart';
import '../../core/theme.dart';
import '../../widgets/common.dart';

/// Look of one figure: icon and colour by what it counts.
(IconData, Color) metricLook(String key) => switch (key) {
      'days' || 'present' => (Icons.event_available_rounded, AixoloColors.success),
      'hours' => (Icons.schedule_rounded, AixoloColors.purple),
      'late' => (Icons.error_rounded, AixoloColors.danger),
      'visits' => (Icons.location_on_rounded, AixoloColors.primary),
      'offsite' => (Icons.near_me_rounded, AixoloColors.purple),
      'orders' || 'count' || 'units' => (Icons.assignment_rounded, AixoloColors.warning),
      'sales' || 'amount' => (Icons.bar_chart_rounded, AixoloColors.primary),
      'collections' || 'collected' => (Icons.currency_rupee_rounded, AixoloColors.success),
      'expenses' => (Icons.account_balance_wallet_rounded, AixoloColors.danger),
      'customers' => (Icons.groups_rounded, AixoloColors.primary),
      'km' || 'distance' => (Icons.add_road_rounded, AixoloColors.muted),
      _ => (Icons.insights_rounded, AixoloColors.primary),
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
  const MetricTile({super.key, required this.metric, required this.label, required this.value, this.big = false});

  final String metric;
  final String label;
  final String value;
  final bool big;

  @override
  Widget build(BuildContext context) {
    final (icon, colour) = metricLook(metric);
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
                Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11, color: AixoloColors.muted)),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(value,
                      style: TextStyle(fontSize: big ? 17 : 15, fontWeight: FontWeight.w800, color: AixoloColors.text)),
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
                    style: const TextStyle(fontSize: 11, color: AixoloColors.muted)),
              ],
            ),
          ),
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
  });

  final Map<String, dynamic> row;
  final String? currency;
  final String saleWord;
  final VoidCallback? onTap;
  final bool highlight;
  final String? subtitle;

  /// Text in the round badge (defaults to the name's initials).
  final String? badge;

  static const _tints = [
    AixoloColors.primary,
    AixoloColors.purple,
    Color(0xFFEA7A1A),
    AixoloColors.success,
    Color(0xFF0D9488),
  ];

  @override
  Widget build(BuildContext context) {
    final name = '${row['employee'] ?? ''}';
    final initials = badge ??
        name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).take(2).map((p) => p[0]).join().toUpperCase();
    final tint = _tints[name.hashCode.abs() % _tints.length];
    String n(String k) => '${(row[k] as num?)?.toInt() ?? 0}';
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: highlight ? AixoloColors.primary : AixoloColors.border, width: highlight ? 1.5 : 1),
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
                  CircleAvatar(
                    radius: 26,
                    backgroundColor: tint.withValues(alpha: 0.12),
                    child: Text(initials,
                        style: TextStyle(color: tint, fontWeight: FontWeight.w800, fontSize: 17)),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16.5)),
                        if (subtitle != null)
                          Text(subtitle!, style: const TextStyle(color: AixoloColors.muted, fontSize: 12.5)),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(_money(row['sales'] as num?, currency),
                          style: const TextStyle(
                              fontWeight: FontWeight.w900, fontSize: 16.5, color: AixoloColors.primary)),
                      const Text('Total value', style: TextStyle(color: AixoloColors.muted, fontSize: 12)),
                    ],
                  ),
                  if (onTap != null) const Icon(Icons.chevron_right_rounded, color: AixoloColors.muted),
                ],
              ),
              const SizedBox(height: 12),
              _row([
                _Mini('days', n('days'), 'Days worked'),
                _Mini('hours', fmtHours(row['hours'] as num?), 'Hours'),
                _Mini('late', n('late'), 'Late days'),
              ]),
              _row([
                _Mini('visits', n('visits'), 'Visits'),
                _Mini('offsite', n('offsite'), 'Offsite'),
                _Mini('orders', n('orders'), saleWord),
              ]),
              _row([
                _Mini('collections', _money(row['collections'] as num?, currency), 'Collected'),
                _Mini('expenses', _money(row['expenses'] as num?, currency), 'Expenses'),
                _Mini('customers', n('customers'), 'New customers'),
                _Mini('km', '${((row['km'] as num?) ?? 0).toStringAsFixed(1)} km', 'Distance'),
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
              if (i > 0) const VerticalDivider(width: 1, thickness: 1, color: AixoloColors.border),
              Expanded(child: Center(child: items[i])),
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
  int _tab = 0;
  Map<String, dynamic>? _overall;
  List<Map<String, dynamic>> _days = [];
  List<Map<String, dynamic>> _visits = [];
  List<Map<String, dynamic>> _orders = [];
  String? _currency;
  String? _error;
  bool _loading = true;

  bool get _demandFlow => Services.auth.profile?.isDemandFlow ?? false;
  String get _saleWord => _demandFlow ? 'Demand' : 'Orders';

  Map<String, dynamic> _query([Map<String, dynamic> extra = const {}]) => {
        'start': fmtDate(widget.start),
        'end': fmtDate(widget.end),
        'member': widget.memberId,
        ...extra,
      };

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
      final api = Services.api;
      final results = await Future.wait([
        api.get('/api/v1/reports/summary', query: _query({'by': 'overall'})),
        api.get('/api/v1/reports/summary', query: _query({'by': 'day'})),
        api.get('/api/v1/reports/visits', query: _query()),
        api.get('/api/v1/reports/${_demandFlow ? 'demands' : 'orders'}', query: _query()),
      ]);
      List<Map<String, dynamic>> rows(Object? r) => (((r as Map)['rows'] as List?) ?? []).cast<Map<String, dynamic>>();
      if (!mounted) return;
      setState(() {
        final overall = rows(results[0]);
        _overall = overall.isEmpty ? {} : overall.first;
        _days = rows(results[1]);
        _visits = rows(results[2]);
        _orders = rows(results[3]);
        _currency = (results[0] as Map)['currency'] as String?;
      });
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _openDay(String date) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => VisitDetailsScreen(
        memberId: widget.memberId,
        name: widget.name,
        date: DateTime.parse(date),
        days: [for (final d in _days) '${d['date']}'],
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final name = widget.name;
    final initials = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).take(2).map((p) => p[0]).join().toUpperCase();
    return Scaffold(
      appBar: AppBar(title: const Text('Employee report')),
      body: _error != null
          ? ErrorView(message: _error!, onRetry: _load)
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
                children: [
                  Row(
                    children: [
                      CircleAvatar(
                        radius: 30,
                        backgroundColor: AixoloColors.primary.withValues(alpha: 0.1),
                        child: Text(initials,
                            style: const TextStyle(
                                color: AixoloColors.primary, fontWeight: FontWeight.w800, fontSize: 20)),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(name, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 19)),
                            Text('${_day(fmtDate(widget.start))} – ${_day(fmtDate(widget.end))}',
                                style: const TextStyle(color: AixoloColors.muted)),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        for (final (i, label) in [
                          (0, 'Overview'),
                          (1, 'Daily'),
                          (2, 'Visits'),
                          (3, _demandFlow ? 'Demands' : 'Orders'),
                        ])
                          Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: ChoiceChip(
                              label: Text(label),
                              selected: _tab == i,
                              showCheckmark: false,
                              selectedColor: AixoloColors.primary,
                              labelStyle: TextStyle(
                                  color: _tab == i ? Colors.white : AixoloColors.text, fontWeight: FontWeight.w700),
                              onSelected: (_) => setState(() => _tab = i),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (_loading && _overall == null)
                    const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator()))
                  else ...switch (_tab) {
                    0 => [..._overview(), const SizedBox(height: 16), ..._daily(title: true)],
                    1 => _daily(),
                    2 => _visitList(),
                    _ => _orderList(),
                  },
                ],
              ),
            ),
    );
  }

  List<Widget> _overview() {
    final o = _overall ?? const {};
    final chronological = _days.reversed.toList();
    return [
      Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                        color: AixoloColors.primary.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12)),
                    child: const Icon(Icons.bar_chart_rounded, color: AixoloColors.primary),
                  ),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Total value', style: TextStyle(color: AixoloColors.muted)),
                      Text(_money(o['sales'] as num?, _currency),
                          style: const TextStyle(
                              fontSize: 24, fontWeight: FontWeight.w900, color: AixoloColors.primary)),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 14),
              _Bars(values: [for (final d in chronological) ((d['sales'] as num?) ?? 0).toDouble()]),
            ],
          ),
        ),
      ),
      const SizedBox(height: 10),
      _tiles([
        MetricTile(metric: 'collections', label: 'Collected', value: _money(o['collections'] as num?, _currency)),
        MetricTile(metric: 'expenses', label: 'Expenses', value: _money(o['expenses'] as num?, _currency)),
        MetricTile(metric: 'visits', label: 'Visits', value: '${o['visits'] ?? 0}'),
        MetricTile(metric: 'orders', label: '$_saleWord count', value: '${o['orders'] ?? 0}'),
        MetricTile(metric: 'customers', label: 'New customers', value: '${o['customers'] ?? 0}'),
        MetricTile(metric: 'km', label: 'Distance', value: '${((o['km'] as num?) ?? 0).toStringAsFixed(1)} km'),
        MetricTile(metric: 'days', label: 'Days worked', value: '${o['days'] ?? 0}'),
        MetricTile(metric: 'hours', label: 'Hours', value: fmtHours(o['hours'] as num?)),
      ]),
    ];
  }

  Widget _tiles(List<Widget> tiles) => Column(
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

  List<Widget> _daily({bool title = false}) {
    final active = _days.where((d) => ((d['visits'] ?? 0) as num) > 0 || ((d['days'] ?? 0) as num) > 0 || ((d['sales'] ?? 0) as num) > 0).toList();
    return [
      if (title)
        const Padding(
          padding: EdgeInsets.fromLTRB(4, 0, 4, 8),
          child: Row(children: [
            Icon(Icons.calendar_month_rounded, color: AixoloColors.primary),
            SizedBox(width: 8),
            Text('Daily breakdown', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
          ]),
        ),
      if (active.isEmpty)
        const Card(child: Padding(padding: EdgeInsets.all(20), child: Text('No activity in this period'))),
      for (final d in active)
        Card(
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: () => _openDay('${d['date']}'),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
              child: Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                        color: AixoloColors.primary.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(10)),
                    child: const Icon(Icons.event_note_rounded, color: AixoloColors.primary, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(_day('${d['date']}'),
                                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                            ),
                            Text(_money(d['sales'] as num?, _currency),
                                style: const TextStyle(fontWeight: FontWeight.w800, color: AixoloColors.primary)),
                          ],
                        ),
                        Text(_weekday('${d['date']}'), style: const TextStyle(color: AixoloColors.muted, fontSize: 12.5)),
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 14,
                          children: [
                            _pair('Visits', '${d['visits'] ?? 0}'),
                            _pair(_saleWord, '${d['orders'] ?? 0}'),
                            _pair('Distance', '${((d['km'] as num?) ?? 0).toStringAsFixed(1)} km'),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right_rounded, color: AixoloColors.muted),
                ],
              ),
            ),
          ),
        ),
    ];
  }

  List<Widget> _visitList() => [
        if (_visits.isEmpty) const Card(child: Padding(padding: EdgeInsets.all(20), child: Text('No visits'))),
        for (final v in _visits)
          VisitCard(visit: v, orderValue: _orderValue(v), currency: _currency, showDate: true),
      ];

  double? _orderValue(Map<String, dynamic> visit) {
    final same = _orders.where((o) => o['customer'] == visit['customer'] && o['date'] == visit['date']);
    if (same.isEmpty) return null;
    return same.fold<double>(0, (s, o) => s + ((o['amount'] as num?) ?? 0).toDouble());
  }

  List<Widget> _orderList() => [
        if (_orders.isEmpty) Card(child: Padding(padding: const EdgeInsets.all(20), child: Text('No ${_saleWord.toLowerCase()}'))),
        for (final o in _orders)
          Card(
            child: ListTile(
              leading: CircleAvatar(
                backgroundColor: AixoloColors.warning.withValues(alpha: 0.12),
                child: const Icon(Icons.assignment_rounded, color: AixoloColors.warning),
              ),
              title: Text('${o['customer'] ?? ''}', style: const TextStyle(fontWeight: FontWeight.w700)),
              subtitle: Text('${o['number'] ?? ''} · ${_day('${o['date']}')} · ${o['status'] ?? ''}'),
              trailing: Text(_money(o['amount'] as num?, _currency),
                  style: const TextStyle(fontWeight: FontWeight.w800, color: AixoloColors.primary)),
            ),
          ),
      ];
}

Widget _pair(String label, String value) => Text.rich(TextSpan(children: [
      TextSpan(text: '$label  ', style: const TextStyle(color: AixoloColors.muted, fontSize: 12.5)),
      TextSpan(text: value, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5)),
    ]));

class _Bars extends StatelessWidget {
  const _Bars({required this.values});

  final List<double> values;

  @override
  Widget build(BuildContext context) {
    final shown = values.length > 20 ? values.sublist(values.length - 20) : values;
    final peak = shown.fold<double>(0, (m, v) => v > m ? v : m);
    return SizedBox(
      height: 70,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (final v in shown)
            Expanded(
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 3),
                height: peak == 0 ? 4 : 6 + 64 * (v / peak),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(6),
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [
                      AixoloColors.primary.withValues(alpha: 0.35),
                      AixoloColors.primary.withValues(alpha: peak == 0 ? 0.35 : 0.35 + 0.6 * (v / peak)),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

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
    final colour = offsite ? AixoloColors.purple : AixoloColors.success;
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
                        style: const TextStyle(color: AixoloColors.muted, fontSize: 12),
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
                          style: const TextStyle(color: AixoloColors.muted, fontSize: 12.5),
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
                      ? const Text('No order', style: TextStyle(color: AixoloColors.muted, fontSize: 12.5))
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
                          color: AixoloColors.primary.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(12)),
                      child: const Icon(Icons.event_note_rounded, color: AixoloColors.primary),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(_day(iso), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
                          Text(_weekday(iso), style: const TextStyle(color: AixoloColors.muted)),
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
                    selectedColor: AixoloColors.primary,
                    labelStyle:
                        TextStyle(color: _filter == key ? Colors.white : AixoloColors.text, fontWeight: FontWeight.w700),
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
