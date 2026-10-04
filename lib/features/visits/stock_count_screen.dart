import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../core/services.dart';
import '../../core/theme.dart';
import '../../widgets/common.dart';

/// Count stock at the customer; the previous count is shown for comparison.
class StockCountScreen extends StatefulWidget {
  const StockCountScreen({super.key, required this.clientId, this.visitId, this.step, this.visitUuid});

  final int clientId;
  final int? visitId;
  final String? visitUuid;
  final Map<String, dynamic>? step;

  @override
  State<StockCountScreen> createState() => _StockCountScreenState();
}

class _StockCountScreenState extends State<StockCountScreen> {
  final _search = TextEditingController();
  final _note = TextEditingController();
  final Map<int, double> _counted = {};

  /// One field per product, so a number can be typed straight in rather than
  /// tapped up from zero. Counting a chiller is reading numbers off shelves.
  final Map<int, TextEditingController> _fields = {};
  final Map<int, FocusNode> _focus = {};

  /// Show only what has been counted, for checking the list at the end.
  bool _onlyCounted = false;
  final Map<int, Map<String, dynamic>> _known = {};
  Map<int, Map<String, dynamic>> _previous = {};
  DateTime? _previousDate;
  List<Map<String, dynamic>> _products = [];
  Timer? _debounce;
  bool _loading = true;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    _note.dispose();
    for (final field in _fields.values) {
      field.dispose();
    }
    for (final node in _focus.values) {
      node.dispose();
    }
    super.dispose();
  }

  TextEditingController _field(int productId) => _fields.putIfAbsent(
      productId, () => TextEditingController(text: _counted[productId] == null ? '' : fmtQty(_counted[productId]!)));

  FocusNode _node(int productId) => _focus.putIfAbsent(productId, FocusNode.new);

  /// Types a number straight into the row.
  void _typed(int productId, String text) {
    final value = double.tryParse(text.trim());
    setState(() {
      if (text.trim().isEmpty) {
        _counted.remove(productId);
      } else if (value != null && value >= 0) {
        _counted[productId] = value;
      }
    });
  }

  /// Moves to the next product without leaving the keyboard.
  void _next(int productId) {
    final rows = _shown;
    final index = rows.indexWhere((p) => p['id'] == productId);
    if (index < 0 || index + 1 >= rows.length) {
      FocusScope.of(context).unfocus();
      return;
    }
    _node(rows[index + 1]['id'] as int).requestFocus();
  }

  /// Last time's numbers, as a starting point. Most shelves move a little,
  /// not from nothing, so correcting a previous count beats typing every one.
  void _copyPrevious() {
    setState(() {
      for (final product in _products) {
        final id = product['id'] as int;
        final was = (_previous[id]?['quantity'] as num?)?.toDouble();
        if (was == null || _counted.containsKey(id)) continue;
        _counted[id] = was;
        _field(id).text = fmtQty(was);
      }
    });
  }

  List<Map<String, dynamic>> get _shown => _onlyCounted
      ? _products.where((p) => _counted.containsKey(p['id'])).toList()
      : _products;

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final q = _search.text.trim();
      final results = await Future.wait<dynamic>([
        Services.api.get('/api/v1/products', query: {'limit': 200, if (q.isNotEmpty) 'q': q}),
        Services.api.get('/api/v1/stock/last', query: {'partner_id': widget.clientId}),
      ]);
      final products = ((results[0] as Map<String, dynamic>)['products'] as List).cast<Map<String, dynamic>>();
      final last = results[1] as Map<String, dynamic>?;
      for (final product in products) {
        _known[product['id'] as int] = product;
      }
      if (!mounted) return;
      setState(() {
        _products = products;
        _previousDate = last == null ? null : parseServerTime(last['date']);
        _previous = {
          for (final line in ((last?['lines'] as List?) ?? []).cast<Map<String, dynamic>>())
            line['product_id'] as int: line,
        };
        _error = null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _setQty(int productId, double qty) {
    setState(() {
      if (qty < 0) {
        _counted.remove(productId);
        _field(productId).text = '';
      } else {
        _counted[productId] = qty;
        _field(productId).text = fmtQty(qty);
      }
    });
  }

  Future<void> _submit() async {
    if (_counted.isEmpty) {
      showSnack(context, 'Count at least one product.');
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() => _busy = true);
    final lines = [
      for (final entry in _counted.entries) {'product_id': entry.key, 'quantity': entry.value},
    ];
    try {
      final visitKnown = widget.visitId != null || widget.visitUuid != null;
      if (widget.step != null && visitKnown) {
        await Services.outbox.submit('/api/v1/visits/${widget.visitId ?? 0}/steps/${widget.step!['id']}', {
          'lines': lines,
          'note': _note.text.trim(),
          if (widget.visitUuid != null) 'visit_uuid': widget.visitUuid,
        }, label: 'Stock count');
      } else {
        await Services.outbox.submit('/api/v1/stock/counts', {
          'partner_id': widget.clientId,
          if (widget.visitId != null) 'visit_id': widget.visitId,
          if (widget.visitUuid != null) 'visit_uuid': widget.visitUuid,
          'lines': lines,
          'note': _note.text.trim(),
        }, label: 'Stock count');
      }
      if (!mounted) return;
      showSnack(context, 'Stock count saved');
      Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) showProblem(context, e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final counted = _counted.length;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Stock Count'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: _loading ? const LinearProgressIndicator(minHeight: 2) : const SizedBox(height: 1),
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _note,
                decoration: InputDecoration(
                  hintText: 'Note (optional)',
                  isDense: true,
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                ),
              ),
              const SizedBox(height: 10),
              GradientButton(
                label: counted == 0
                    ? 'Save count'
                    : 'Save count · $counted ${counted == 1 ? 'product' : 'products'}',
                icon: Icons.inventory_rounded,
                busy: _busy,
                onPressed: counted == 0 || _busy ? null : _submit,
              ),
            ],
          ),
        ),
      ),
      body: Column(
        children: [
          _header(),
          Expanded(
            child: _error != null
                ? ErrorView(message: _error!, onRetry: _load)
                : _shown.isEmpty && !_loading
                    ? const EmptyView(icon: Icons.inventory_2_outlined, text: 'No products match')
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
                        itemCount: _shown.length,
                        itemBuilder: (_, i) => _productCard(_shown[i]),
                      ),
          ),
        ],
      ),
    );
  }

  /// Search, what has been counted so far, and a way to start from last time.
  Widget _header() {
    final copyable = _previous.isNotEmpty &&
        _products.any((p) => _previous.containsKey(p['id']) && !_counted.containsKey(p['id']));
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      child: Column(
        children: [
          TextField(
            controller: _search,
            onChanged: (_) {
              _debounce?.cancel();
              _debounce = Timer(const Duration(milliseconds: 400), _load);
            },
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search_rounded),
              hintText: 'Search product or SKU',
              isDense: true,
              filled: true,
              fillColor: AppColors.background,
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
            ),
          ),
          const SizedBox(height: 9),
          SizedBox(
            height: 32,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                _chip(Icons.checklist_rounded, '${_counted.length} counted', AppColors.primary),
                const SizedBox(width: 7),
                _chip(Icons.history_rounded,
                    _previousDate == null ? 'First count here' : 'Last ${fmtDate(_previousDate!)}',
                    AppColors.muted),
                if (copyable) ...[
                  const SizedBox(width: 7),
                  _action(Icons.content_copy_rounded, 'Start from last count', _copyPrevious),
                ],
                if (_counted.isNotEmpty) ...[
                  const SizedBox(width: 7),
                  _action(
                      _onlyCounted ? Icons.list_rounded : Icons.filter_alt_rounded,
                      _onlyCounted ? 'Show all' : 'Counted only',
                      () => setState(() => _onlyCounted = !_onlyCounted)),
                  const SizedBox(width: 7),
                  _action(Icons.backspace_outlined, 'Clear', () {
                    setState(() {
                      _counted.clear();
                      for (final field in _fields.values) {
                        field.clear();
                      }
                      _onlyCounted = false;
                    });
                  }),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _chip(IconData icon, String text, Color tint) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
        decoration: BoxDecoration(
          color: tint.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: tint),
            const SizedBox(width: 5),
            Text(text, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: tint)),
          ],
        ),
      );

  Widget _action(IconData icon, String text, VoidCallback onTap) => Material(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 14, color: AppColors.primary),
                const SizedBox(width: 5),
                Text(text,
                    style: const TextStyle(
                        fontSize: 11.5, fontWeight: FontWeight.w700, color: AppColors.primary)),
              ],
            ),
          ),
        ),
      );

  /// One product: what it was last time, what it is now, and the difference.
  ///
  /// The number is typed straight into the row, because counting a chiller is
  /// reading numbers off shelves, not tapping one up from zero twenty times.
  /// The plus and minus are there for the odd correction.
  Widget _productCard(Map<String, dynamic> product) {
    final id = product['id'] as int;
    final qty = _counted[id];
    final previousQty = (_previous[id]?['quantity'] as num?)?.toDouble();
    final delta = qty != null && previousQty != null ? qty - previousQty : null;
    final on = qty != null;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(12, 9, 8, 9),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: on ? AppColors.primary.withValues(alpha: 0.4) : AppColors.border),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('${product['name']}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                const SizedBox(height: 3),
                Row(
                  children: [
                    if (product['sku'] != null)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: Text('${product['sku']}',
                            style: const TextStyle(fontSize: 11.5, color: AppColors.muted)),
                      ),
                    Flexible(
                      child: Text(
                        previousQty == null
                            ? 'Not counted before'
                            : 'Last: ${fmtQty(previousQty)} ${product['uom'] ?? ''}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 11.5, color: AppColors.muted),
                      ),
                    ),
                    if (delta != null && delta != 0) ...[
                      const SizedBox(width: 7),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(
                          color: (delta > 0 ? AppColors.success : AppColors.danger).withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text('${delta > 0 ? '+' : ''}${fmtQty(delta)}',
                            style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                                color: delta > 0 ? AppColors.success : AppColors.danger)),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          _stepButton(Icons.remove_rounded, on && qty > 0 ? () => _setQty(id, qty - 1) : null),
          SizedBox(
            width: 58,
            child: TextField(
              controller: _field(id),
              focusNode: _node(id),
              onChanged: (text) => _typed(id, text),
              onSubmitted: (_) => _next(id),
              textAlign: TextAlign.center,
              textInputAction: TextInputAction.next,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
              decoration: InputDecoration(
                hintText: '0',
                hintStyle: TextStyle(
                    fontWeight: FontWeight.w700, fontSize: 16, color: AppColors.muted.withValues(alpha: 0.5)),
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 9),
                filled: true,
                fillColor: on ? AppColors.primary.withValues(alpha: 0.08) : AppColors.background,
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(11), borderSide: BorderSide.none),
              ),
            ),
          ),
          _stepButton(Icons.add_rounded, () => _setQty(id, (qty ?? 0) + 1)),
        ],
      ),
    );
  }

  Widget _stepButton(IconData icon, VoidCallback? onTap) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: Icon(icon, size: 19, color: onTap == null ? AppColors.border : AppColors.primary),
        ),
      );
}
