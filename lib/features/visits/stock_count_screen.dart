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
    super.dispose();
  }

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
      } else {
        _counted[productId] = qty;
      }
    });
  }

  Future<void> _typeQty(int productId) async {
    final controller = TextEditingController(text: fmtQty(_counted[productId] ?? 0));
    final value = await showDialog<double>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('${_known[productId]?['name'] ?? 'Quantity'}'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(labelText: 'Counted quantity'),
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
      if (mounted) showSnack(context, e.toString());
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
                : _products.isEmpty && !_loading
                    ? const EmptyView(icon: Icons.inventory_2_outlined, text: 'No products match')
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
                        itemCount: _products.length,
                        itemBuilder: (_, i) => _productCard(_products[i]),
                      ),
          ),
        ],
      ),
    );
  }

  /// Search, the last count's date, and how much has been counted so far.
  Widget _header() => Container(
        color: Colors.white,
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
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
            const SizedBox(height: 10),
            Row(
              children: [
                _chip(
                  Icons.checklist_rounded,
                  '${_counted.length} counted',
                  AppColors.primary,
                ),
                const SizedBox(width: 8),
                _chip(
                  Icons.history_rounded,
                  _previousDate == null ? 'First count here' : 'Last ${fmtDate(_previousDate!)}',
                  AppColors.muted,
                ),
                const Spacer(),
                if (_counted.isNotEmpty)
                  TextButton(
                    onPressed: () => setState(_counted.clear),
                    child: const Text('Clear'),
                  ),
              ],
            ),
          ],
        ),
      );

  Widget _chip(IconData icon, String text, Color tint) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
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

  /// One product: what it was last time, what it is now, and the difference.
  Widget _productCard(Map<String, dynamic> product) {
    final id = product['id'] as int;
    final qty = _counted[id];
    final previousQty = (_previous[id]?['quantity'] as num?)?.toDouble();
    final delta = qty != null && previousQty != null ? qty - previousQty : null;
    final on = qty != null;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: on ? AppColors.primary.withValues(alpha: 0.35) : AppColors.border),
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
                    Text(
                      previousQty == null
                          ? 'Not counted before'
                          : 'Last: ${fmtQty(previousQty)} ${product['uom'] ?? ''}',
                      style: const TextStyle(fontSize: 11.5, color: AppColors.muted),
                    ),
                    if (delta != null && delta != 0) ...[
                      const SizedBox(width: 8),
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
          if (!on)
            OutlinedButton(
              onPressed: () => _setQty(id, 0),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(64, 36),
                padding: const EdgeInsets.symmetric(horizontal: 12),
              ),
              child: const Text('Count'),
            )
          else
            Container(
              decoration: BoxDecoration(
                color: AppColors.background,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _stepButton(Icons.remove_rounded, () => _setQty(id, qty - 1)),
                  InkWell(
                    onTap: () => _typeQty(id),
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      width: 46,
                      alignment: Alignment.center,
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Text(fmtQty(qty),
                          style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15)),
                    ),
                  ),
                  _stepButton(Icons.add_rounded, () => _setQty(id, qty + 1)),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _stepButton(IconData icon, VoidCallback onTap) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(7),
          child: Icon(icon, size: 18, color: AppColors.primary),
        ),
      );
}
