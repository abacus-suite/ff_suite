import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../tasks/task_widgets.dart';
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
  final Map<int, double> _freeQ = {};
  String? _freeReason;
  final _freeNote = TextEditingController();
  static const _freeReasons = ['Sample', 'Display', 'Damage cover', 'Festival offer', 'Other'];
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
        if (widget.client != null) 'partner_id': widget.client!['id'],
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
      _cart.entries.fold(0.0, (sum, e) => sum + ((_known[e.key]?['price'] as num?) ?? 0) * (e.value > 0 ? e.value : 0));

  /// The taxes the products carry, on what is in the cart. The server works out the real figure.
  double get _tax => _cart.entries.fold(0.0, (sum, e) {
        final p = _known[e.key];
        final price = (p?['price'] as num?) ?? 0;
        final rate = (p?['tax_percent'] as num?) ?? 0;
        return sum + price * (e.value > 0 ? e.value : 0) * rate / 100;
      });

  double get _units => _cart.values.fold(0.0, (a, b) => a + (b > 0 ? b : 0));

  bool get _anyFree => _freeQ.values.any((v) => v > 0);

  /// What is missing before the person can go on, or null when it is complete.
  String? get _problem {
    final order = _cart.values.any((v) => v > 0);
    if (!order && !_anyFree) return 'Enter the order quantity, or the free quantity.';
    if (!order) return 'Enter the order quantity: free goods go with an order.';
    if (_anyFree && _freeReason == null) return 'Say why the quantity is free.';
    if (_anyFree && _freeReason == 'Other' && _freeNote.text.trim().isEmpty) return 'Describe the free reason.';
    return null;
  }

  Future<void> _review() async {
    final problem = _problem;
    if (problem != null) {
      showSnack(context, problem);
      return;
    }
    final lines = _cart.entries
        .where((e) => e.value > 0 && _known[e.key] != null)
        .map((e) => {..._known[e.key]!, 'qty': e.value})
        .toList();
    final reason = _freeReason == 'Other' ? _freeNote.text.trim() : _freeReason;
    final free = [
      for (final e in _freeQ.entries)
        if (e.value > 0 && _known[e.key] != null)
          {'product_id': e.key, 'name': _known[e.key]!['name'], 'qty': e.value, 'reason': reason},
    ];
    final placed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => OrderReviewScreen(client: widget.client!, lines: lines, free: free)),
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

  Widget _section(IconData icon, String title, String note, Widget child) => Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [BoxShadow(color: const Color(0xFF1B3A7A).withValues(alpha: 0.06), blurRadius: 12, offset: const Offset(0, 4))],
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(color: AppColors.primary.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(13)),
              child: Icon(icon, color: AppColors.primary, size: 21),
            ),
            const SizedBox(width: 12),
            Expanded(child: Text(title, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 17))),
          ]),
          const SizedBox(height: 6),
          Text(note, style: const TextStyle(color: AppColors.muted, fontSize: 13)),
          const SizedBox(height: 10),
          child,
        ]),
      );

  /// Quantities for the whole range on one screen: what is ordered, and what is given free.
  Widget _quantities() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 24),
      children: [
        _section(Icons.shopping_cart_rounded, 'Order quantity', 'What the customer is ordering, at the customer price.',
            QtyGrid(products: _products, values: _cart, onChanged: () => setState(() {}))),
        _section(
          Icons.redeem_rounded,
          'Free quantity',
          'Kept apart from the order. Goes with an order.',
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            QtyGrid(products: _products, values: _freeQ, onChanged: () => setState(() {})),
            if (_anyFree) ...[
              const SizedBox(height: 12),
              const Text('Free reason *', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5)),
              const SizedBox(height: 8),
              Wrap(spacing: 8, runSpacing: 8, children: [
                for (final reason in _freeReasons)
                  ChoiceChip(
                    label: Text(reason),
                    selected: _freeReason == reason,
                    onSelected: (_) => setState(() => _freeReason = reason),
                  ),
              ]),
              if (_freeReason == 'Other') ...[
                const SizedBox(height: 10),
                TextField(
                  controller: _freeNote,
                  maxLines: 2,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(hintText: 'Describe the free reason'),
                ),
              ],
            ],
          ]),
        ),
      ],
    );
  }

  /// The way on: a note on what is missing, and Next.
  Widget _nextBar() {
    final problem = _problem;
    return SafeArea(
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          boxShadow: [BoxShadow(color: Color(0x1A1B3A7A), blurRadius: 16, offset: Offset(0, -4))],
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          if (problem != null)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(11),
              decoration: BoxDecoration(color: AppColors.warning.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(14)),
              child: Row(children: [
                const Icon(Icons.info_outline_rounded, color: AppColors.warning, size: 18),
                const SizedBox(width: 8),
                Expanded(child: Text(problem, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13))),
              ]),
            )
          else
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(children: [
                Expanded(
                    child: Text('${fmtQty(_units)} units${_anyFree ? ' + free' : ''}',
                        style: const TextStyle(color: AppColors.muted, fontWeight: FontWeight.w700))),
                Text(fmtMoney(_total + _tax), style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 19)),
              ]),
            ),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: problem == null ? _review : null,
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
              icon: const Icon(Icons.arrow_forward_rounded),
              label: const Text('Next: summary'),
            ),
          ),
        ]),
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
      bottomNavigationBar: widget.client == null ? null : _nextBar(),
      body: Column(children: [
        _searchBar(),
        if (_categories.isNotEmpty) _chips(),
        if (_loading) const LinearProgressIndicator(minHeight: 2),
        if (_error != null) Padding(padding: const EdgeInsets.all(12), child: Text(_error!)),
        Expanded(
          child: _products.isEmpty && !_loading
              ? const Center(child: Text('No products found', style: TextStyle(color: AppColors.muted)))
              : widget.client != null
                  ? _quantities()
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
