import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../core/services.dart';
import '../../core/theme.dart';
import '../../widgets/common.dart';
import '../../widgets/group_kit.dart';
import '../../widgets/member_picker.dart';

class OrdersScreen extends StatefulWidget {
  const OrdersScreen({super.key, this.embedded = false});

  final bool embedded;

  @override
  State<OrdersScreen> createState() => _OrdersScreenState();
}

class _OrdersScreenState extends State<OrdersScreen> {
  List<Map<String, dynamic>> _orders = [];
  Map<String, dynamic>? _summary;
  bool _loading = true;
  String? _error;
  String _member = 'me';
  String _period = 'today';
  DateTimeRange _range = Periods.range('today');
  String _groupBy = 'none';
  String _status = 'all';
  final _search = TextEditingController();
  Timer? _debounce;
  final Set<String> _collapsed = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  bool get _demandFlow => Services.auth.profile?.isDemandFlow ?? false;

  Map<String, dynamic> get _query => {
        'member': _member,
        'start': fmtDate(_range.start),
        'end': fmtDate(_range.end),
        if (_search.text.trim().isNotEmpty) 'q': _search.text.trim(),
      };

  Future<void> _load() async {
    setState(() => _loading = true);
    if (_orders.isEmpty && _summary == null) {
      // The last copy of this view first; the fresh one replaces it.
      final saved = await Future.wait([
        Services.api.peek(_demandFlow ? '/api/v1/demands' : '/api/v1/orders', query: {..._query, 'limit': 1000}),
        Services.api.peek('/api/v1/orders/summary', query: _query),
      ]);
      if (mounted && saved[0] is List && saved[1] is Map && _orders.isEmpty) {
        setState(() {
          _orders = (saved[0] as List).cast<Map<String, dynamic>>();
          _summary = (saved[1] as Map).cast<String, dynamic>();
        });
      }
    }
    try {
      final results = await Future.wait([
        Services.api.get(_demandFlow ? '/api/v1/demands' : '/api/v1/orders', query: {..._query, 'limit': 1000}),
        Services.api.get('/api/v1/orders/summary', query: _query),
      ]);
      if (!mounted) return;
      setState(() {
        _orders = (results[0] as List).cast<Map<String, dynamic>>();
        _summary = results[1] as Map<String, dynamic>;
        _error = null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _showOrder(int id) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _OrderDetail(orderId: id, demandFlow: _demandFlow),
    );
  }

  List<GroupOption> get _groupOptions => [
        ...dateGroups,
        if (_member != 'me') const GroupOption('employee', 'Employee', Icons.person_rounded),
        const GroupOption('customer', 'Customer', Icons.storefront_rounded),
        if (_demandFlow) const GroupOption('route', 'Beat', Icons.route_rounded),
        if (_demandFlow) const GroupOption('product', 'Product', Icons.inventory_2_rounded),
      ];

  List<Map<String, dynamic>> get _visible =>
      _status == 'all' ? _orders : _orders.where((o) => o['state'] == _status).toList();

  /// (sortable key, title, rows, value) per group; one untitled section when not grouped.
  List<(String, String, List<Map<String, dynamic>>, double)> _sections() {
    final rows = _visible;
    if (_groupBy == 'none') return [('', '', rows, 0)];
    final titles = <String, String>{};
    final members = <String, List<Map<String, dynamic>>>{};
    final values = <String, double>{};
    void add(String key, String title, Map<String, dynamic> row, double value) {
      titles[key] = title;
      members.putIfAbsent(key, () => []).add(row);
      values[key] = (values[key] ?? 0) + value;
    }

    for (final o in rows) {
      final amount = (o['amount_total'] as num? ?? 0).toDouble();
      switch (_groupBy) {
        case 'employee':
          final e = o['employee'] as Map?;
          add('${e?['id']}', '${e?['name'] ?? '—'}', o, amount);
        case 'customer':
          final c = o['client'] as Map?;
          add('${c?['name']}', '${c?['name'] ?? '—'}', o, amount);
        case 'route':
          final r = o['route'] as Map?;
          add('${r?['name'] ?? '~'}', '${r?['name'] ?? 'No beat'}', o, amount);
        case 'product':
          for (final p in ((o['products'] as List?) ?? []).cast<Map<String, dynamic>>()) {
            add('${p['name']}', '${p['name']}', o, (p['subtotal'] as num? ?? 0).toDouble());
          }
        default:
          final date = parseServerTime(o['date']);
          if (date == null) continue;
          final bucket = dateBucket(date.toLocal(), _groupBy);
          add(bucket.$1, bucket.$2, o, amount);
      }
    }
    final keys = titles.keys.toList();
    if (dateGroups.any((g) => g.key == _groupBy)) {
      keys.sort((a, b) => b.compareTo(a));
    } else {
      keys.sort((a, b) => values[b]!.compareTo(values[a]!));
    }
    return [for (final k in keys) (k, titles[k]!, members[k]!, values[k]!)];
  }

  Widget _row(Map<String, dynamic> o) {
    final products = ((o['products'] as List?) ?? []).length;
    return Card(
      child: ListTile(
        title: Text('${o['name']} · ${(o['client'] as Map?)?['name'] ?? ''}'),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text([
              '${fmtDate(parseServerTime(o['date'])!)} ${fmtTime(o['date'])}',
              if (products > 0) '$products products' else if (o['line_count'] != null) '${o['line_count']} products',
              if (_member != 'me' && (o['employee'] as Map?)?['name'] != null) '${(o['employee'] as Map)['name']}',
              if ((o['route'] as Map?)?['name'] != null) '${(o['route'] as Map)['name']}',
            ].join(' · ')),
            Row(
              children: [
                StatusBadge('${o['state']}', label: '${o['state_label']}'),
                if ((o['quoted_percent'] as num? ?? 0) > 0)
                  Padding(
                    padding: const EdgeInsets.only(left: 6),
                    child: Text('${(o['quoted_percent'] as num).round()}% quoted',
                        style: const TextStyle(fontSize: 11, color: AppColors.muted)),
                  ),
              ],
            ),
          ],
        ),
        isThreeLine: true,
        trailing: Text(fmtMoney(o['amount_total'] as num?, o['currency'] as String?),
            style: const TextStyle(fontWeight: FontWeight.w700)),
        onTap: () => _showOrder(o['id'] as int),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final summary = _summary;
    final word = _demandFlow ? 'demands' : 'orders';
    final statuses = <String, String>{
      for (final o in _orders) '${o['state']}': '${o['state_label'] ?? o['state']}',
    };
    final sections = _sections();
    final periodLabel = Periods.choices.firstWhere((p) => p.$1 == _period).$2;
    return Scaffold(
      appBar: AppBar(
          automaticallyImplyLeading: !widget.embedded, title: Text(_demandFlow ? 'My Demands' : 'My Orders')),
      body: Column(
        children: [
          Container(
            color: Colors.white,
            padding: const EdgeInsets.only(bottom: 8),
            child: Column(
              children: [
                PeriodChips(
                  period: _period,
                  range: _range,
                  onChanged: (period, range) {
                    setState(() {
                      _period = period;
                      _range = range;
                    });
                    _load();
                  },
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: TextField(
                    controller: _search,
                    onChanged: (_) {
                      _debounce?.cancel();
                      _debounce = Timer(const Duration(milliseconds: 450), _load);
                    },
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.search_rounded),
                      hintText: 'Search number, customer or product',
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                SizedBox(
                  height: 40,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    children: [
                      MemberPicker(
                        value: _member,
                        dense: true,
                        onChanged: (value) {
                          setState(() {
                            _member = value;
                            if (value == 'me' && _groupBy == 'employee') _groupBy = 'none';
                          });
                          _load();
                        },
                      ),
                      const SizedBox(width: 6),
                      GroupByChip(
                          value: _groupBy, options: _groupOptions, onChanged: (v) => setState(() => _groupBy = v)),
                      if (statuses.length > 1) ...[
                        const SizedBox(width: 6),
                        ChoiceChip(
                          label: const Text('All'),
                          selected: _status == 'all',
                          onSelected: (_) => setState(() => _status = 'all'),
                        ),
                        for (final entry in statuses.entries)
                          Padding(
                            padding: const EdgeInsets.only(left: 6),
                            child: ChoiceChip(
                              label: Text(entry.value),
                              selected: _status == entry.key,
                              onSelected: (_) => setState(() => _status = entry.key),
                            ),
                          ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (_loading) const LinearProgressIndicator(minHeight: 2),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 100),
                children: [
                  if (_error != null) Text(_error!),
                  if (summary != null)
                    Card(
                      child: ListTile(
                        leading: const Icon(Icons.today),
                        title: Text('$periodLabel: ${summary['count']} $word'),
                        subtitle: Text('${fmtMoney(summary['amount_total'] as num?, summary['currency'] as String?)}'
                            '${_demandFlow ? ' at PTR' : ' incl. tax'}'
                            '${_period == 'custom' ? ' · ${prettyDay(_range.start)} – ${prettyDay(_range.end)}' : ''}'),
                      ),
                    ),
                  if (_visible.isEmpty && !_loading)
                    Padding(
                      padding: const EdgeInsets.all(32),
                      child: Center(child: Text('No $word in this period')),
                    ),
                  for (final section in sections) ...[
                    if (_groupBy != 'none')
                      GroupHeader(
                        title: section.$2,
                        count: section.$3.length,
                        totals: [fmtMoney(section.$4, summary?['currency'] as String?)],
                        expanded: !_collapsed.contains(section.$1),
                        onTap: () => setState(() {
                          if (!_collapsed.remove(section.$1)) _collapsed.add(section.$1);
                        }),
                      ),
                    if (_groupBy == 'none' || !_collapsed.contains(section.$1))
                      for (final o in section.$3) _row(o),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _OrderDetail extends StatelessWidget {
  const _OrderDetail({required this.orderId, required this.demandFlow});

  final int orderId;
  final bool demandFlow;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<dynamic>(
      future: Services.api.get(demandFlow ? '/api/v1/demands/$orderId' : '/api/v1/orders/$orderId'),
      builder: (context, snap) {
        if (snap.hasError) return Padding(padding: const EdgeInsets.all(24), child: Text('${snap.error}'));
        if (!snap.hasData) return const Padding(padding: EdgeInsets.all(48), child: Center(child: CircularProgressIndicator()));
        final o = snap.data as Map<String, dynamic>;
        final lines = ((o['lines'] as List?) ?? []).cast<Map<String, dynamic>>();
        final currency = o['currency'] as String?;
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.6,
          builder: (context, controller) => ListView(
            controller: controller,
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
            children: [
              Text('${o['name']} · ${o['state_label']}', style: Theme.of(context).textTheme.titleLarge),
              Text('${(o['client'] as Map?)?['name'] ?? ''}'),
              const Divider(),
              for (final l in lines)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text('${(l['product'] as Map)['name']}'),
                  subtitle: Text('${fmtQty(l['qty'] as num)} × ${fmtMoney(l['price_unit'] as num?, currency)}'
                      '${(l['discount'] as num? ?? 0) > 0 ? ' · ${l['discount']}% off' : ''}'
                      '${(l['quoted_qty'] as num? ?? 0) > 0 ? ' · ${fmtQty(l['quoted_qty'] as num)} quoted' : ''}'),
                  trailing: Text(fmtMoney(l['subtotal'] as num?, currency)),
                ),
              const Divider(),
              if (!demandFlow) ...[
                ListTile(contentPadding: EdgeInsets.zero, title: const Text('Untaxed'),
                    trailing: Text(fmtMoney(o['amount_untaxed'] as num?, currency))),
                ListTile(contentPadding: EdgeInsets.zero, title: const Text('Tax'),
                    trailing: Text(fmtMoney(o['amount_tax'] as num?, currency))),
              ],
              ListTile(contentPadding: EdgeInsets.zero, title: const Text('Total'),
                  trailing: Text(fmtMoney(o['amount_total'] as num?, currency),
                      style: const TextStyle(fontWeight: FontWeight.bold))),
            ],
          ),
        );
      },
    );
  }
}
