import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../core/services.dart';
import '../../core/theme.dart';
import 'order_review_screen.dart';

/// Product catalogue with a cart for one client. Pops `true` when an order was placed.
class CatalogScreen extends StatefulWidget {
  const CatalogScreen({super.key, this.client});

  /// Null when opened just to look up products and prices - no cart then.
  final Map<String, dynamic>? client;

  @override
  State<CatalogScreen> createState() => _CatalogScreenState();
}

class _CatalogScreenState extends State<CatalogScreen> {
  final _search = TextEditingController();
  Timer? _debounce;
  List<Map<String, dynamic>> _products = [];
  List<Map<String, dynamic>> _categories = [];
  List<Map<String, dynamic>> _schemes = [];
  int? _categoryId;
  final Map<int, double> _cart = {};
  final Map<int, Map<String, dynamic>> _known = {};
  bool _loading = true;
  String? _error;
  String _base = '';
  Map<String, String> _headers = const {};

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    _base = await Services.api.url('');
    _headers = await Services.api.authHeaders();
    try {
      final categories = await Services.api.get('/api/v1/products/categories') as List;
      _categories = categories.cast<Map<String, dynamic>>();
    } catch (_) {
      // Category chips are optional.
    }
    try {
      final foc = await Services.api.get('/api/v1/foc/schemes',
          query: {if (widget.client != null) 'partner_id': widget.client!['id']}) as Map<String, dynamic>;
      _schemes = ((foc['schemes'] as List?) ?? []).cast<Map<String, dynamic>>();
    } catch (_) {
      // No FOC module: no badges.
    }
    await _load();
  }

  /// The schemes that give something free on this product.
  List<Map<String, dynamic>> _schemesFor(Map<String, dynamic> p) => _schemes.where((s) {
        final products = ((s['product_ids'] as List?) ?? []);
        if (products.isNotEmpty) return products.contains(p['id']);
        return ((s['category_ids'] as List?) ?? []).contains((p['category'] as Map?)?['id']);
      }).toList();

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final q = _search.text.trim();
      final data = await Services.api.get('/api/v1/products', query: {
        'limit': 300,
        if (q.isNotEmpty) 'q': q,
        if (_categoryId != null) 'category_id': _categoryId,
      }) as Map<String, dynamic>;
      final products = (data['products'] as List).cast<Map<String, dynamic>>();
      for (final p in products) {
        _known[p['id'] as int] = p;
      }
      setState(() => _products = products);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _setQty(int productId, double qty) {
    setState(() {
      if (qty <= 0) {
        _cart.remove(productId);
      } else {
        _cart[productId] = qty;
      }
    });
  }

  double get _total =>
      _cart.entries.fold(0.0, (sum, e) => sum + ((_known[e.key]?['price'] as num?) ?? 0) * e.value);

  Future<void> _review() async {
    final lines = _cart.entries.map((e) => {..._known[e.key]!, 'qty': e.value}).toList();
    final placed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => OrderReviewScreen(client: widget.client!, lines: lines)),
    );
    if (placed == true && mounted) Navigator.of(context).pop(true);
  }

  Future<void> _typeQty(int productId) async {
    final controller = TextEditingController(text: fmtQty(_cart[productId] ?? 0));
    final value = await showDialog<double>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(_known[productId]?['name'] as String? ?? 'Quantity'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(labelText: 'Quantity'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, double.tryParse(controller.text)), child: const Text('OK')),
        ],
      ),
    );
    // Disposed after the dialog's closing animation: the field is still on screen until then.
    WidgetsBinding.instance.addPostFrameCallback((_) => Future.delayed(const Duration(milliseconds: 400), controller.dispose));
    if (value != null) _setQty(productId, value);
  }

  @override
  Widget build(BuildContext context) {
    final itemCount = _cart.length;
    return Scaffold(
      appBar: AppBar(title: Text(widget.client == null ? 'Products' : 'Order · ${widget.client!['name']}')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            child: TextField(
              controller: _search,
              onChanged: (_) {
                _debounce?.cancel();
                _debounce = Timer(const Duration(milliseconds: 400), _load);
              },
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'Search product or SKU',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
          ),
          if (_categories.isNotEmpty)
            SizedBox(
              height: 48,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                children: [
                  for (final category in [<String, dynamic>{'id': null, 'name': 'All'}, ..._categories])
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: ChoiceChip(
                        label: Text(category['name'] as String),
                        selected: _categoryId == category['id'],
                        onSelected: (_) {
                          setState(() => _categoryId = category['id'] as int?);
                          _load();
                        },
                      ),
                    ),
                ],
              ),
            ),
          if (_loading) const LinearProgressIndicator(),
          if (_error != null) Padding(padding: const EdgeInsets.all(12), child: Text(_error!)),
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.only(bottom: 16),
              itemCount: _products.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (_, i) {
                final p = _products[i];
                final id = p['id'] as int;
                final qty = _cart[id] ?? 0;
                return ListTile(
                  leading: SizedBox(
                    width: 48,
                    height: 48,
                    child: p['has_image'] == true
                        ? ClipRRect(
                            borderRadius: BorderRadius.circular(6),
                            child: Image.network('$_base/api/v1/products/$id/image',
                                headers: _headers,
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => const Icon(Icons.inventory_2)),
                          )
                        : const Icon(Icons.inventory_2),
                  ),
                  title: Text(p['name'] as String),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text([
                        if (p['sku'] != null) p['sku'],
                        '${fmtMoney(p['price'] as num?)} / ${p['uom']}',
                      ].join(' · ')),
                      for (final scheme in _schemesFor(p))
                        Padding(
                          padding: const EdgeInsets.only(top: 3),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                                color: const Color(0xFFE6F7EE), borderRadius: BorderRadius.circular(20)),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.redeem_rounded, size: 13, color: AixoloColors.success),
                                const SizedBox(width: 4),
                                Flexible(
                                  child: Text('${scheme['summary']}',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                          fontSize: 11.5, color: AixoloColors.success, fontWeight: FontWeight.w700)),
                                ),
                              ],
                            ),
                          ),
                        ),
                      // The three trade prices, when the office has set them:
                      // what the outlet pays, what it sells at, what it earns.
                      if (p['mrp'] != null || p['ptr'] != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 3),
                          child: Wrap(
                            spacing: 6,
                            runSpacing: 4,
                            children: [
                              if (p['ptr'] != null) PriceChip(label: 'PTR', value: p['ptr'] as num),
                              if (p['mrp'] != null)
                                PriceChip(label: 'MRP', value: p['mrp'] as num, tone: AixoloColors.teal),
                              if (retailMargin(p) != null)
                                PriceChip(
                                  label: 'Margin',
                                  text: '${retailMargin(p)!.toStringAsFixed(1)}%',
                                  tone: AixoloColors.success,
                                ),
                            ],
                          ),
                        ),
                    ],
                  ),
                  isThreeLine: p['mrp'] != null || p['ptr'] != null,
                  trailing: widget.client == null
                      ? null
                      : qty == 0
                      ? IconButton.filledTonal(onPressed: () => _setQty(id, 1), icon: const Icon(Icons.add))
                      : Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(onPressed: () => _setQty(id, qty - 1), icon: const Icon(Icons.remove_circle_outline)),
                            InkWell(
                              onTap: () => _typeQty(id),
                              child: SizedBox(
                                width: 40,
                                child: Text(fmtQty(qty), textAlign: TextAlign.center,
                                    style: const TextStyle(fontWeight: FontWeight.bold)),
                              ),
                            ),
                            IconButton(onPressed: () => _setQty(id, qty + 1), icon: const Icon(Icons.add_circle_outline)),
                          ],
                        ),
                );
              },
            ),
          ),
        ],
      ),
      bottomNavigationBar: itemCount == 0 || widget.client == null
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: FilledButton(
                  onPressed: _review,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('$itemCount product${itemCount == 1 ? '' : 's'} · Review'),
                        Text(fmtMoney(_total), style: const TextStyle(fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ),
                ),
              ),
            ),
    );
  }
}

/// What the outlet earns between PTR and MRP, the way the trade quotes it.
double? retailMargin(Map<String, dynamic> product) {
  final ptr = (product['ptr'] as num?)?.toDouble();
  final mrp = (product['mrp'] as num?)?.toDouble();
  if (ptr == null || mrp == null || ptr <= 0) return null;
  return (mrp - ptr) / ptr * 100;
}

/// A small tinted price tag: "PTR 45".
class PriceChip extends StatelessWidget {
  const PriceChip({super.key, required this.label, this.value, this.text, this.tone = AixoloColors.primary});

  final String label;
  final num? value;
  final String? text;
  final Color tone;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(color: tone.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(20)),
      child: Text(
        '$label ${text ?? fmtMoney(value)}',
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: tone),
      ),
    );
  }
}
