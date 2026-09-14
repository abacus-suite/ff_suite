import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../core/services.dart';
import '../../core/theme.dart';
import '../../widgets/common.dart';

String _day(dynamic iso) {
  final d = DateTime.tryParse('${iso ?? ''}')?.toLocal();
  if (d == null) return '–';
  const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  return '${d.day} ${months[d.month - 1]} ${d.year}';
}

/// Every product this customer has taken from us, newest first.
class ProductHistoryScreen extends StatefulWidget {
  const ProductHistoryScreen({super.key, required this.clientId, required this.clientName});

  final int clientId;
  final String clientName;

  @override
  State<ProductHistoryScreen> createState() => _ProductHistoryScreenState();
}

class _ProductHistoryScreenState extends State<ProductHistoryScreen> {
  Map<String, dynamic>? _data;
  String? _error;
  bool _loading = true;
  String _find = '';
  String _sort = 'recent';

  String get _path => '/api/v1/clients/${widget.clientId}/products';

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
    final saved = await Services.api.peek(_path);
    if (mounted && saved is Map && _data == null) setState(() => _data = saved.cast<String, dynamic>());
    try {
      final data = await Services.api.get(_path) as Map<String, dynamic>;
      if (mounted) setState(() => _data = data);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<Map<String, dynamic>> get _products {
    final rows = ((_data?['products'] as List?) ?? []).cast<Map<String, dynamic>>();
    final needle = _find.trim().toLowerCase();
    final shown = rows
        .where((p) => needle.isEmpty || '${p['name']} ${p['sku'] ?? ''}'.toLowerCase().contains(needle))
        .toList();
    if (_sort == 'quantity') {
      shown.sort((a, b) => ((b['quantity'] as num?) ?? 0).compareTo((a['quantity'] as num?) ?? 0));
    } else if (_sort == 'times') {
      shown.sort((a, b) => ((b['times'] as num?) ?? 0).compareTo((a['times'] as num?) ?? 0));
    }
    return shown;
  }

  @override
  Widget build(BuildContext context) {
    final currency = _data?['currency'] as String?;
    final products = _products;
    final all = ((_data?['products'] as List?) ?? []).length;
    return Scaffold(
      appBar: AppBar(title: const Text('Product history')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
          children: [
            Text(widget.clientName, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            const SizedBox(height: 10),
            if (_data != null)
              Row(
                children: [
                  Expanded(child: _Figure(label: 'Products', value: '$all', colour: AppColors.primary)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _Figure(
                      label: 'Total value',
                      value: fmtMoney((_data?['total_amount'] as num?) ?? 0, currency),
                      colour: AppColors.success,
                    ),
                  ),
                ],
              ),
            const SizedBox(height: 10),
            TextField(
              onChanged: (v) => setState(() => _find = v),
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search_rounded),
                hintText: 'Search product or SKU',
                isDense: true,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              children: [
                for (final (key, label) in [('recent', 'Recent'), ('quantity', 'Most quantity'), ('times', 'Most often')])
                  ChoiceChip(
                    label: Text(label),
                    selected: _sort == key,
                    onSelected: (_) => setState(() => _sort = key),
                  ),
              ],
            ),
            if (_loading && _data == null)
              const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator())),
            if (_error != null && _data == null) ErrorView(message: _error!, onRetry: _load),
            if (_data != null && products.isEmpty)
              const EmptyView(icon: Icons.inventory_2_outlined, text: 'No products taken yet'),
            for (final p in products)
              Card(
                margin: const EdgeInsets.only(top: 10),
                child: InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => ProductMovesScreen(
                      clientId: widget.clientId,
                      clientName: widget.clientName,
                      productId: p['id'] as int,
                      productName: '${p['name']}',
                    ),
                  )),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
                    child: Row(
                      children: [
                        Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: AppColors.primary.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(Icons.inventory_2_rounded, color: AppColors.primary),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('${p['name']}',
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                              if (p['sku'] != null)
                                Text('SKU ${p['sku']}', style: const TextStyle(color: AppColors.muted, fontSize: 12)),
                              const SizedBox(height: 6),
                              Wrap(
                                spacing: 12,
                                runSpacing: 4,
                                children: [
                                  _Pair('Qty', fmtQty((p['quantity'] as num?) ?? 0)),
                                  _Pair('Times', '${p['times'] ?? 0}'),
                                  _Pair('Last', _day(p['last_date'])),
                                ],
                              ),
                            ],
                          ),
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(fmtMoney((p['amount'] as num?) ?? 0, currency),
                                style: const TextStyle(fontWeight: FontWeight.w800, color: AppColors.primary)),
                            const Icon(Icons.chevron_right_rounded, color: AppColors.muted),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// One product at one customer: every time it was asked for.
class ProductMovesScreen extends StatefulWidget {
  const ProductMovesScreen({
    super.key,
    required this.clientId,
    required this.clientName,
    required this.productId,
    required this.productName,
  });

  final int clientId;
  final String clientName;
  final int productId;
  final String productName;

  @override
  State<ProductMovesScreen> createState() => _ProductMovesScreenState();
}

class _ProductMovesScreenState extends State<ProductMovesScreen> {
  Map<String, dynamic>? _data;
  String? _error;
  bool _loading = true;

  String get _path => '/api/v1/clients/${widget.clientId}/products/${widget.productId}';

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
      final data = await Services.api.get(_path) as Map<String, dynamic>;
      if (mounted) setState(() => _data = data);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Color _stateColour(String? state) => switch (state) {
        'supplied' || 'sale' || 'done' => AppColors.success,
        'quoted' || 'partial' || 'sent' => AppColors.primary,
        'draft' => AppColors.muted,
        _ => AppColors.warning,
      };

  @override
  Widget build(BuildContext context) {
    final data = _data;
    final currency = data?['currency'] as String?;
    final product = (data?['product'] as Map?)?.cast<String, dynamic>();
    final history = ((data?['history'] as List?) ?? []).cast<Map<String, dynamic>>();
    return Scaffold(
      appBar: AppBar(title: Text(widget.productName, overflow: TextOverflow.ellipsis)),
      body: _error != null && data == null
          ? ErrorView(message: _error!, onRetry: _load)
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
                children: [
                  Text(widget.clientName, style: const TextStyle(color: AppColors.muted)),
                  if (product != null && (product['sku'] != null || product['category'] != null))
                    Text([if (product['sku'] != null) 'SKU ${product['sku']}', if (product['category'] != null) product['category']].join(' · '),
                        style: const TextStyle(color: AppColors.muted, fontSize: 12.5)),
                  const SizedBox(height: 10),
                  if (_loading && data == null)
                    const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator())),
                  if (data != null) ...[
                    Row(
                      children: [
                        Expanded(child: _Figure(label: 'Times', value: '${data['times'] ?? 0}', colour: AppColors.purple)),
                        const SizedBox(width: 8),
                        Expanded(
                            child: _Figure(
                                label: 'Asked', value: fmtQty((data['quantity'] as num?) ?? 0), colour: AppColors.warning)),
                        const SizedBox(width: 8),
                        Expanded(
                            child: _Figure(
                                label: 'Quoted', value: fmtQty((data['quoted'] as num?) ?? 0), colour: AppColors.success)),
                      ],
                    ),
                    const SizedBox(height: 8),
                    _Figure(
                      label: 'Total value',
                      value: fmtMoney((data['amount'] as num?) ?? 0, currency),
                      colour: AppColors.primary,
                    ),
                    const Padding(
                      padding: EdgeInsets.fromLTRB(4, 16, 4, 6),
                      child: Text('Every time', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                    ),
                    if (history.isEmpty) const EmptyView(icon: Icons.history_rounded, text: 'Nothing recorded'),
                    for (final h in history)
                      Card(
                        margin: const EdgeInsets.only(bottom: 10),
                        child: Padding(
                          padding: const EdgeInsets.all(14),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text('${h['number']}',
                                        style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: _stateColour(h['state'] as String?).withValues(alpha: 0.12),
                                      borderRadius: BorderRadius.circular(20),
                                    ),
                                    child: Text('${h['state_label'] ?? h['state']}',
                                        style: TextStyle(
                                            color: _stateColour(h['state'] as String?),
                                            fontSize: 12,
                                            fontWeight: FontWeight.w700)),
                                  ),
                                ],
                              ),
                              Text(
                                [_day(h['date']), if (h['kind'] == 'order') 'Order' else 'Demand'].join(' · '),
                                style: const TextStyle(color: AppColors.muted, fontSize: 12.5),
                              ),
                              const Divider(height: 18),
                              Wrap(
                                spacing: 22,
                                runSpacing: 8,
                                children: [
                                  _Stacked('Asked', fmtQty((h['quantity'] as num?) ?? 0)),
                                  if (h['kind'] == 'demand') _Stacked('Quoted', fmtQty((h['quoted'] as num?) ?? 0)),
                                  if (h['delivered'] != null) _Stacked('Delivered', fmtQty((h['delivered'] as num?) ?? 0)),
                                  _Stacked('Price', fmtMoney((h['price'] as num?) ?? 0, currency)),
                                  _Stacked('Value', fmtMoney((h['amount'] as num?) ?? 0, currency)),
                                  if (h['employee'] is Map) _Stacked('By', '${(h['employee'] as Map)['name']}'),
                                  if (h['distributor'] is Map && h['kind'] == 'demand')
                                    _Stacked('Distributor', '${(h['distributor'] as Map)['name']}'),
                                  if (h['site'] != null) _Stacked('Site', '${h['site']}'),
                                  if (h['foc'] == true) const _Stacked('Scheme', 'Free (FOC)'),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ],
              ),
            ),
    );
  }
}

class _Figure extends StatelessWidget {
  const _Figure({required this.label, required this.value, required this.colour});

  final String label;
  final String value;
  final Color colour;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(color: colour.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(14)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontSize: 11.5, color: AppColors.muted)),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(value, style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: colour)),
          ),
        ],
      ),
    );
  }
}

class _Pair extends StatelessWidget {
  const _Pair(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Text.rich(TextSpan(children: [
        TextSpan(text: '$label ', style: const TextStyle(color: AppColors.muted, fontSize: 12.5)),
        TextSpan(text: value, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5)),
      ]));
}

class _Stacked extends StatelessWidget {
  const _Stacked(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: const TextStyle(fontSize: 11.5, color: AppColors.muted)),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5)),
        ],
      );
}
