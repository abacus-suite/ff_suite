import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../core/services.dart';
import '../../core/theme.dart';
import '../../widgets/common.dart';

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

  @override
  void initState() {
    super.initState();
    _load();
  }

  bool get _demandFlow => Services.auth.profile?.isDemandFlow ?? false;

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      // On the demand flow the outlet's request is a demand, not a quotation.
      final results = await Future.wait([
        Services.api.get(_demandFlow ? '/api/v1/demands' : '/api/v1/orders'),
        Services.api.get('/api/v1/orders/summary'),
      ]);
      setState(() {
        _orders = (results[0] as List).cast<Map<String, dynamic>>();
        _summary = results[1] as Map<String, dynamic>;
        _error = null;
      });
    } catch (e) {
      setState(() => _error = e.toString());
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

  @override
  Widget build(BuildContext context) {
    final summary = _summary;
    return Scaffold(
      appBar: AppBar(
          automaticallyImplyLeading: !widget.embedded,
          title: Text(_demandFlow ? 'My Demands' : 'My Orders')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.all(12),
          children: [
            if (_loading) const LinearProgressIndicator(),
            if (_error != null) Text(_error!),
            if (summary != null)
              Card(
                child: ListTile(
                  leading: const Icon(Icons.today),
                  title: Text('Today: ${summary['count']} ${_demandFlow ? 'demands' : 'orders'}'),
                  subtitle: Text('${fmtMoney(summary['amount_total'] as num?, summary['currency'] as String?)}'
                      '${_demandFlow ? ' at PTR' : ' incl. tax'}'),
                ),
              ),
            if (_orders.isEmpty && !_loading)
              Padding(
                padding: const EdgeInsets.all(32),
                child: Center(child: Text(_demandFlow ? 'No demands yet' : 'No orders yet')),
              ),
            for (final o in _orders)
              Card(
                child: ListTile(
                  title: Text('${o['name']} · ${(o['client'] as Map?)?['name'] ?? ''}'),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('${fmtDate(parseServerTime(o['date'])!)} ${fmtTime(o['date'])}'
                          '${o['line_count'] != null ? ' · ${o['line_count']} products' : ''}'),
                      Row(
                        children: [
                          StatusBadge('${o['state']}', label: '${o['state_label']}'),
                          // How much of what the outlet asked for has reached
                          // the distributor.
                          if ((o['quoted_percent'] as num? ?? 0) > 0)
                            Padding(
                              padding: const EdgeInsets.only(left: 6),
                              child: Text('${(o['quoted_percent'] as num).round()}% quoted',
                                  style: const TextStyle(fontSize: 11, color: AixoloColors.muted)),
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
