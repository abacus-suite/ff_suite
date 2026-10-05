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

  /// The taxes the products carry, on what is in the cart. The server works out the real figure.
  double get _tax => _cart.entries.fold(0.0, (sum, e) {
        final p = _known[e.key];
        final price = (p?['price'] as num?) ?? 0;
        final rate = (p?['tax_percent'] as num?) ?? 0;
        return sum + price * e.value * rate / 100;
      });

  double get _units => _cart.values.fold(0.0, (a, b) => a + b);

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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
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
    WidgetsBinding.instance
        .addPostFrameCallback((_) => Future.delayed(const Duration(milliseconds: 400), controller.dispose));
    if (value != null) _setQty(productId, value);
  }

  // ------------------------------------------------------------------ pieces
  Widget _picture(Map<String, dynamic> p, double size) {
    final id = p['id'] as int;
    final fallback = Container(
      width: size,
      height: size,
      color: AppColors.primary.withValues(alpha: 0.08),
      child: Icon(Icons.inventory_2_rounded, color: AppColors.primary.withValues(alpha: 0.6), size: size * 0.4),
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(size * 0.24),
      child: SizedBox(
        width: size,
        height: size,
        child: p['has_image'] == true && _base.isNotEmpty
            ? Image.network('$_base/api/v1/products/$id/image',
                headers: _headers, fit: BoxFit.cover, errorBuilder: (_, __, ___) => fallback)
            : fallback,
      ),
    );
  }

  /// "Add", or a stepper once the product is in the cart.
  Widget _control(int id, double qty) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 220),
      switchInCurve: Curves.easeOutBack,
      transitionBuilder: (child, anim) => ScaleTransition(scale: anim, child: FadeTransition(opacity: anim, child: child)),
      child: qty == 0
          ? FilledButton.icon(
              key: ValueKey('add$id'),
              onPressed: () => _setQty(id, 1),
              style: FilledButton.styleFrom(
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text('Add'),
            )
          : Container(
              key: ValueKey('step$id'),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                _stepButton(Icons.remove_rounded, () => _setQty(id, qty - 1)),
                InkWell(
                  onTap: () => _typeQty(id),
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    constraints: const BoxConstraints(minWidth: 28),
                    alignment: Alignment.center,
                    child: Text(fmtQty(qty),
                        style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: AppColors.primary)),
                  ),
                ),
                _stepButton(Icons.add_rounded, () => _setQty(id, qty + 1)),
              ]),
            ),
    );
  }

  Widget _stepButton(IconData icon, VoidCallback onTap) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(padding: const EdgeInsets.all(6), child: Icon(icon, size: 19, color: AppColors.primary)),
      );

  Widget _tag(String text, Color tint, {IconData? icon}) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
        decoration: BoxDecoration(color: tint.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(20)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (icon != null) ...[Icon(icon, size: 12, color: tint), const SizedBox(width: 4)],
          Flexible(
            child: Text(text,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, color: tint)),
          ),
        ]),
      );

  /// One product on a single compact row: picture, name and price, the
  /// small tags, and the add control on the right.
  Widget _card(Map<String, dynamic> p) {
    final id = p['id'] as int;
    final qty = _cart[id] ?? 0;
    final inCart = qty > 0;
    final tax = (p['tax_percent'] as num?) ?? 0;
    final margin = retailMargin(p);
    final schemes = _schemesFor(p);
    final tags = <Widget>[
      if (tax > 0) _tag('+${fmtQty(tax)}% tax', AppColors.warning),
      if (p['mrp'] != null) _tag('MRP ${fmtMoney(p['mrp'] as num)}', AppColors.teal),
      if (margin != null) _tag('${margin.toStringAsFixed(1)}% margin', AppColors.success),
      for (final scheme in schemes) _tag('${scheme['summary']}', AppColors.success, icon: Icons.redeem_rounded),
    ];
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(10, 9, 10, 9),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: inCart ? AppColors.primary : Colors.transparent, width: 1.5),
        boxShadow: [BoxShadow(color: const Color(0xFF1B3A7A).withValues(alpha: 0.06), blurRadius: 10, offset: const Offset(0, 3))],
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
        _picture(p, 54),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Text('${p['name']}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14, height: 1.2)),
            const SizedBox(height: 2),
            Row(children: [
              Text(fmtMoney(p['price'] as num?),
                  style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14, color: AppColors.primary)),
              Text(' / ${p['uom']}', style: const TextStyle(fontSize: 11.5, color: AppColors.muted)),
              if (p['sku'] != null)
                Flexible(
                  child: Text('  ·  ${p['sku']}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 11, color: AppColors.muted)),
                ),
            ]),
            if (tags.isNotEmpty) ...[
              const SizedBox(height: 5),
              Wrap(spacing: 5, runSpacing: 4, children: tags),
            ],
          ]),
        ),
        if (widget.client != null) ...[
          const SizedBox(width: 8),
          SizedBox(width: 106, child: Align(alignment: Alignment.centerRight, child: _control(id, qty))),
        ],
      ]),
    );
  }

  Widget _searchBar() => Container(
        margin: const EdgeInsets.fromLTRB(16, 4, 16, 8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          boxShadow: [BoxShadow(color: const Color(0xFF1B3A7A).withValues(alpha: 0.06), blurRadius: 12, offset: const Offset(0, 4))],
        ),
        child: TextField(
          controller: _search,
          onChanged: (_) {
            _debounce?.cancel();
            _debounce = Timer(const Duration(milliseconds: 400), _load);
            setState(() {});
          },
          decoration: InputDecoration(
            prefixIcon: const Icon(Icons.search_rounded, color: AppColors.muted),
            suffixIcon: _search.text.isEmpty
                ? null
                : IconButton(
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () {
                      _search.clear();
                      _load();
                      setState(() {});
                    },
                  ),
            hintText: 'Search product or SKU',
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none,
            contentPadding: const EdgeInsets.symmetric(vertical: 15),
          ),
        ),
      );

  Widget _chips() => SizedBox(
        height: 46,
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          children: [
            for (final category in [<String, dynamic>{'id': null, 'name': 'All'}, ..._categories])
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: GestureDetector(
                  onTap: () {
                    setState(() => _categoryId = category['id'] as int?);
                    _load();
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    alignment: Alignment.center,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    decoration: BoxDecoration(
                      gradient: _categoryId == category['id'] ? AppColors.brandGradient : null,
                      color: _categoryId == category['id'] ? null : Colors.white,
                      borderRadius: BorderRadius.circular(22),
                      border: Border.all(color: _categoryId == category['id'] ? Colors.transparent : AppColors.border),
                    ),
                    child: Text('${category['name']}',
                        style: TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 13,
                            color: _categoryId == category['id'] ? Colors.white : AppColors.text)),
                  ),
                ),
              ),
          ],
        ),
      );

  /// What is in the cart, to change or remove before reviewing.
  Future<void> _showCart() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheet) => StatefulBuilder(
        builder: (context, set) {
          final entries = _cart.entries.toList();
          return SafeArea(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.75),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                  child: Row(children: [
                    const Expanded(child: Text('Your cart', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 19))),
                    TextButton(
                      onPressed: entries.isEmpty
                          ? null
                          : () {
                              setState(_cart.clear);
                              Navigator.pop(sheet);
                            },
                      child: const Text('Clear'),
                    ),
                  ]),
                ),
                Flexible(
                  child: ListView(
                    shrinkWrap: true,
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                    children: [
                      for (final e in entries)
                        Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(color: AppColors.background, borderRadius: BorderRadius.circular(16)),
                          child: Row(children: [
                            _picture(_known[e.key]!, 44),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text('${_known[e.key]!['name']}',
                                  maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
                            ),
                            Container(
                              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
                              child: Row(mainAxisSize: MainAxisSize.min, children: [
                                _stepButton(Icons.remove_rounded, () {
                                  _setQty(e.key, e.value - 1);
                                  set(() {});
                                }),
                                Text(fmtQty(e.value), style: const TextStyle(fontWeight: FontWeight.w900)),
                                _stepButton(Icons.add_rounded, () {
                                  _setQty(e.key, e.value + 1);
                                  set(() {});
                                }),
                              ]),
                            ),
                          ]),
                        ),
                    ],
                  ),
                ),
              ]),
            ),
          );
        },
      ),
    );
  }

  Widget _cartBar() {
    final count = _cart.length;
    return AnimatedSlide(
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
      offset: count == 0 || widget.client == null ? const Offset(0, 1.5) : Offset.zero,
      child: SafeArea(
        child: Container(
          margin: const EdgeInsets.fromLTRB(14, 0, 14, 12),
          padding: const EdgeInsets.fromLTRB(16, 10, 10, 10),
          decoration: BoxDecoration(
            gradient: AppColors.brandGradient,
            borderRadius: BorderRadius.circular(24),
            boxShadow: [BoxShadow(color: AppColors.primary.withValues(alpha: 0.35), blurRadius: 22, offset: const Offset(0, 10))],
          ),
          child: Row(children: [
            Expanded(
              child: InkWell(
                onTap: _showCart,
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                  Row(children: [
                    const Icon(Icons.shopping_basket_rounded, color: Colors.white70, size: 16),
                    const SizedBox(width: 6),
                    Text('$count product${count == 1 ? '' : 's'} · ${fmtQty(_units)} units',
                        style: const TextStyle(color: Colors.white70, fontSize: 12.5, fontWeight: FontWeight.w700)),
                    const Icon(Icons.keyboard_arrow_up_rounded, color: Colors.white70, size: 18),
                  ]),
                  const SizedBox(height: 2),
                  Text(fmtMoney(_total + _tax),
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 20)),
                  if (_tax > 0)
                    Text('incl. ${fmtMoney(_tax)} tax', style: const TextStyle(color: Colors.white60, fontSize: 11)),
                ]),
              ),
            ),
            FilledButton(
              onPressed: _review,
              style: FilledButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: AppColors.primary,
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
              child: const Row(mainAxisSize: MainAxisSize.min, children: [
                Text('Review', style: TextStyle(fontWeight: FontWeight.w900)),
                SizedBox(width: 4),
                Icon(Icons.arrow_forward_rounded, size: 18),
              ]),
            ),
          ]),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(widget.client == null ? 'Products' : 'Choose products',
              style: const TextStyle(fontWeight: FontWeight.w900)),
          if (widget.client != null)
            Text('${widget.client!['name']}', style: const TextStyle(fontSize: 12.5, color: AppColors.muted)),
        ]),
      ),
      bottomNavigationBar: widget.client == null ? null : _cartBar(),
      body: Column(children: [
        _searchBar(),
        if (_categories.isNotEmpty) _chips(),
        if (_loading) const LinearProgressIndicator(minHeight: 2),
        if (_error != null) Padding(padding: const EdgeInsets.all(12), child: Text(_error!)),
        Expanded(
          child: _products.isEmpty && !_loading
              ? const Center(child: Text('No products found', style: TextStyle(color: AppColors.muted)))
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 24),
                  itemCount: _products.length,
                  itemBuilder: (_, i) => _card(_products[i]),
                ),
        ),
      ]),
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
  const PriceChip({super.key, required this.label, this.value, this.text, this.tone = AppColors.primary});

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
