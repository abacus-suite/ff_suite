import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../core/services.dart';
import '../../core/theme.dart';
import '../../widgets/common.dart';
import '../../widgets/group_kit.dart';
import '../../widgets/member_picker.dart';
import 'catalog_screen.dart';

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
  String _sort = 'latest';
  String _base = '';
  Map<String, String> _headers = const {};

  @override
  void initState() {
    super.initState();
    _load();
    _loadImageKeys();
  }

  /// Where to fetch product pictures from, with this session's key.
  Future<void> _loadImageKeys() async {
    final base = await Services.api.url('');
    final headers = await Services.api.authHeaders();
    if (mounted) {
      setState(() {
        _base = base;
        _headers = headers;
      });
    }
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

  /// Newest first, biggest first, or by customer.
  List<Map<String, dynamic>> _sorted(List<Map<String, dynamic>> rows) {
    final out = [...rows];
    switch (_sort) {
      case 'amount':
        out.sort((a, b) =>
            ((b['amount_total'] as num?) ?? 0).compareTo((a['amount_total'] as num?) ?? 0));
      case 'customer':
        out.sort((a, b) => '${(a['client'] as Map?)?['name']}'
            .toLowerCase()
            .compareTo('${(b['client'] as Map?)?['name']}'.toLowerCase()));
      default:
        out.sort((a, b) => '${b['date']}'.compareTo('${a['date']}'));
    }
    return out;
  }

  int _countOf(String state) => _orders.where((o) => o['state'] == state).length;

  /// The card for one order or demand.
  Widget _row(Map<String, dynamic> o) {
    final products = ((o['products'] as List?) ?? []).cast<Map<String, dynamic>>();
    final count = products.isNotEmpty ? products.length : ((o['line_count'] as num?) ?? 0).toInt();
    final date = parseServerTime(o['date']);
    final route = asText((o['route'] as Map?)?['name']);
    final state = '${o['state']}';
    final tone = switch (state) {
      'approved' || 'sale' || 'done' => AppColors.success,
      'cancelled' || 'cancel' => AppColors.danger,
      'draft' => AppColors.muted,
      _ => AppColors.primary,
    };
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => _showOrder(o['id'] as int),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 10, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                        color: tone.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(13)),
                    child: Icon(_demandFlow ? Icons.assignment_rounded : Icons.receipt_long_rounded,
                        size: 20, color: tone),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('${o['name']}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15)),
                        Text('${(o['client'] as Map?)?['name'] ?? ''}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 12.5, color: AppColors.muted)),
                      ],
                    ),
                  ),
                  const SizedBox(width: 6),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                        decoration: BoxDecoration(
                            color: tone.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(20)),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                                state == 'approved' || state == 'sale' || state == 'done'
                                    ? Icons.check_circle_rounded
                                    : (state == 'cancelled' || state == 'cancel'
                                        ? Icons.cancel_rounded
                                        : Icons.schedule_rounded),
                                size: 13,
                                color: tone),
                            const SizedBox(width: 4),
                            Text('${o['state_label'] ?? state}',
                                style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, color: tone)),
                          ],
                        ),
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Text(fmtMoney(o['amount_total'] as num?, o['currency'] as String?),
                              style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15)),
                          const Icon(Icons.chevron_right_rounded, color: AppColors.muted),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Container(height: 1, color: AppColors.border),
              const SizedBox(height: 8),
              Row(
                children: [
                  if (date != null)
                    _meta(Icons.calendar_today_rounded, prettyDay(date.toLocal()), fmtTime(o['date'])),
                  if (count > 0) ...[
                    _divider(),
                    _meta(Icons.inventory_2_rounded, '$count product${count == 1 ? '' : 's'}', ''),
                  ],
                  if (route != null) ...[
                    _divider(),
                    _meta(Icons.place_rounded, route, ''),
                  ],
                  if (_member != 'me' && asText((o['employee'] as Map?)?['name']) != null) ...[
                    _divider(),
                    _meta(Icons.person_rounded, '${(o['employee'] as Map)['name']}', ''),
                  ],
                ],
              ),
              if (products.isNotEmpty) ...[
                const SizedBox(height: 10),
                SizedBox(
                  height: 46,
                  child: Row(
                    children: [
                      for (final product in products.take(3)) _thumb(product),
                      if (count > 3)
                        Container(
                          width: 46,
                          height: 46,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: AppColors.primary.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text('+${count - 3}',
                              style: const TextStyle(
                                  fontWeight: FontWeight.w800, fontSize: 12.5, color: AppColors.primary)),
                        ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _divider() => Container(
        width: 1,
        height: 24,
        margin: const EdgeInsets.symmetric(horizontal: 8),
        color: AppColors.border,
      );

  Widget _meta(IconData icon, String value, String hint) => Flexible(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 26,
              height: 26,
              decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(9)),
              child: Icon(icon, size: 14, color: AppColors.primary),
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(value,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                  if (hint.isNotEmpty)
                    Text(hint, style: const TextStyle(fontSize: 10.5, color: AppColors.muted)),
                ],
              ),
            ),
          ],
        ),
      );

  Widget _thumb(Map<String, dynamic> product) => Padding(
        padding: const EdgeInsets.only(right: 8),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: SizedBox(
            width: 46,
            height: 46,
            child: product['has_image'] == true && _base.isNotEmpty
                ? Image.network('$_base/api/v1/products/${product['id']}/image',
                    headers: _headers,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => _thumbFallback())
                : _thumbFallback(),
          ),
        ),
      );

  Widget _thumbFallback() => Container(
        color: AppColors.background,
        child: const Icon(Icons.inventory_2_outlined, size: 18, color: AppColors.muted),
      );

  Widget _statBox(IconData icon, String value, String label, Color tint) => Expanded(
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 3),
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
          decoration: BoxDecoration(
              color: tint.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(14)),
          child: Column(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(color: tint, shape: BoxShape.circle),
                child: Icon(icon, size: 17, color: Colors.white),
              ),
              const SizedBox(height: 6),
              Text(value, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
              Text(label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 10.5, color: AppColors.muted)),
            ],
          ),
        ),
      );

  Widget _sortPill() => Container(
        padding: const EdgeInsets.only(left: 10, right: 2),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: AppColors.border),
        ),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<String>(
            value: _sort,
            isDense: true,
            borderRadius: BorderRadius.circular(14),
            icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 18, color: AppColors.muted),
            style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: AppColors.text),
            items: const [
              DropdownMenuItem(value: 'latest', child: Text('Latest')),
              DropdownMenuItem(value: 'amount', child: Text('Biggest')),
              DropdownMenuItem(value: 'customer', child: Text('Customer')),
            ],
            onChanged: (value) => value == null ? null : setState(() => _sort = value),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final summary = _summary;
    final word = _demandFlow ? 'demands' : 'orders';
    final one = _demandFlow ? 'demand' : 'order';
    final statuses = <String, String>{
      for (final o in _orders) '${o['state']}': '${o['state_label'] ?? o['state']}',
    };
    final sections = _sections();
    final periodLabel = Periods.choices.firstWhere((p) => p.$1 == _period).$2;
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 6, 12, 6),
              child: Row(
                children: [
                  if (!widget.embedded && Navigator.of(context).canPop())
                    IconButton(
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(Icons.arrow_back_rounded)),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(_demandFlow ? 'My Demands' : 'My Orders',
                            style: const TextStyle(
                                fontSize: 24, fontWeight: FontWeight.w900, color: AppColors.text)),
                        Text('Track your $word',
                            style: const TextStyle(fontSize: 12.5, color: AppColors.muted)),
                      ],
                    ),
                  ),
                  FilledButton.icon(
                    onPressed: () async {
                      await Navigator.of(context)
                          .push(MaterialPageRoute(builder: (_) => const CatalogScreen()));
                      _load();
                    },
                    style: FilledButton.styleFrom(
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    ),
                    icon: const Icon(Icons.add_rounded, size: 18),
                    label: const Text('New'),
                  ),
                ],
              ),
            ),
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
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 6),
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.border),
                ),
                child: TextField(
                  controller: _search,
                  onChanged: (_) {
                    _debounce?.cancel();
                    _debounce = Timer(const Duration(milliseconds: 450), _load);
                  },
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search_rounded, color: AppColors.muted),
                    hintText: 'Search number, customer or product...',
                    border: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    contentPadding: EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),
            ),
            SizedBox(
              height: 44,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
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
                  const SizedBox(width: 8),
                  GroupByChip(
                      value: _groupBy, options: _groupOptions, onChanged: (v) => setState(() => _groupBy = v)),
                  const SizedBox(width: 8),
                  _sortPill(),
                  if (statuses.length > 1) ...[
                    const SizedBox(width: 8),
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
            if (_loading) const LinearProgressIndicator(minHeight: 2),
            Expanded(
              child: RefreshIndicator(
                onRefresh: _load,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
                  children: [
                    if (_error != null) Text(_error!),
                    Card(
                      margin: const EdgeInsets.only(bottom: 14),
                      child: Padding(
                        padding: const EdgeInsets.all(8),
                        child: Row(
                          children: [
                            _statBox(Icons.description_rounded, '${_orders.length}',
                                'Total ${_demandFlow ? 'demands' : 'orders'}', AppColors.primary),
                            _statBox(Icons.check_circle_rounded,
                                '${_countOf('approved') + _countOf('sale') + _countOf('done')}', 'Approved',
                                AppColors.success),
                            _statBox(Icons.schedule_rounded,
                                '${_countOf('submitted') + _countOf('draft') + _countOf('sent')}', 'Waiting',
                                AppColors.warning),
                            _statBox(Icons.cancel_rounded,
                                '${_countOf('cancelled') + _countOf('cancel')}', 'Cancelled', AppColors.danger),
                          ],
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Row(
                        children: [
                          Text(periodLabel,
                              style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
                          const Spacer(),
                          if (summary != null)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                              decoration: BoxDecoration(
                                color: AppColors.primary.withValues(alpha: 0.08),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(
                                  '${summary['count']} ${summary['count'] == 1 ? one : word}  ·  '
                                  '${fmtMoney(summary['amount_total'] as num?, summary['currency'] as String?)}',
                                  style: const TextStyle(
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w800,
                                      color: AppColors.primary)),
                            ),
                        ],
                      ),
                    ),
                    if (_visible.isEmpty && !_loading)
                      Padding(
                        padding: const EdgeInsets.all(28),
                        child: EmptyView(
                            icon: Icons.receipt_long_rounded, text: 'No $word in this period'),
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
                        for (final o in _sorted(section.$3)) _row(o),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
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
