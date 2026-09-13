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
    return Scaffold(
      appBar: AppBar(title: const Text('Stock Count')),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: GradientButton(
            label: 'Save count (${_counted.length})',
            icon: Icons.inventory_rounded,
            busy: _busy,
            onPressed: _submit,
          ),
        ),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: TextField(
              controller: _search,
              onChanged: (_) {
                _debounce?.cancel();
                _debounce = Timer(const Duration(milliseconds: 400), _load);
              },
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search_rounded),
                hintText: 'Search product or SKU',
                isDense: true,
              ),
            ),
          ),
          if (_previousDate != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Row(
                children: [
                  const Icon(Icons.history_rounded, size: 16, color: AixoloColors.muted),
                  const SizedBox(width: 6),
                  Text('Last count ${fmtDate(_previousDate!)}',
                      style: const TextStyle(fontSize: 12, color: AixoloColors.muted)),
                ],
              ),
            ),
          if (_loading) const LinearProgressIndicator(),
          if (_error != null) Padding(padding: const EdgeInsets.all(12), child: Text(_error!)),
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.only(bottom: 12),
              itemCount: _products.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (_, i) {
                final product = _products[i];
                final id = product['id'] as int;
                final qty = _counted[id];
                final previous = _previous[id];
                final previousQty = (previous?['quantity'] as num?)?.toDouble();
                final delta = qty != null && previousQty != null ? qty - previousQty : null;
                return ListTile(
                  title: Text('${product['name']}'),
                  subtitle: Text([
                    if (product['sku'] != null) '${product['sku']}',
                    previousQty != null ? 'Last: ${fmtQty(previousQty)} ${product['uom']}' : 'Not counted before',
                    if (delta != null) '${delta >= 0 ? '+' : ''}${fmtQty(delta)}',
                  ].join(' · ')),
                  trailing: qty == null
                      ? IconButton.filledTonal(onPressed: () => _setQty(id, 0), icon: const Icon(Icons.add))
                      : Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                                onPressed: () => _setQty(id, qty - 1), icon: const Icon(Icons.remove_circle_outline)),
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
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: TextField(
              controller: _note,
              decoration: const InputDecoration(labelText: 'Note (optional)', isDense: true),
            ),
          ),
        ],
      ),
    );
  }
}
