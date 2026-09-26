import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:uuid/uuid.dart';

import '../../core/format.dart';
import '../../core/geo.dart';
import '../../core/services.dart';
import '../../core/theme.dart';

class OrderReviewScreen extends StatefulWidget {
  const OrderReviewScreen({super.key, required this.client, required this.lines});

  final Map<String, dynamic> client;
  final List<Map<String, dynamic>> lines;

  @override
  State<OrderReviewScreen> createState() => _OrderReviewScreenState();
}

class _OrderReviewScreenState extends State<OrderReviewScreen> {
  bool get demandFlow => Services.auth.profile?.isDemandFlow ?? false;

  final _note = TextEditingController();
  // One id per review screen: retrying after a network error cannot create a duplicate order.
  final String _uuid = const Uuid().v4();
  bool _busy = false;

  /// Free units the schemes give this cart (from the server), and whether it could be asked.
  List<Map<String, dynamic>> _free = [];
  bool _freeChecked = false;
  bool _manualAllowed = false;

  /// Free goods the rep adds by hand: product, qty, reason.
  final List<Map<String, dynamic>> _manual = [];

  /// Who will supply this order: chosen here, before it is sent.
  List<Map<String, dynamic>> _distributors = [];
  int? _distributorId;

  @override
  void initState() {
    super.initState();
    _loadFoc();
    _loadDistributors();
  }

  /// The distributors this outlet can be supplied by, with the usual one first.
  Future<void> _loadDistributors() async {
    try {
      final data = await Services.api.get('/api/v1/distributors',
          query: {'partner_id': widget.client['id']}) as Map<String, dynamic>;
      if (!mounted) return;
      setState(() {
        _distributors = ((data['distributors'] as List?) ?? []).cast<Map<String, dynamic>>();
        _distributorId = data['suggested_id'] as int?;
      });
    } catch (_) {
      // No distributors set up: the order goes straight to the customer.
    }
  }

  Future<void> _loadFoc() async {
    try {
      final results = await Future.wait([
        Services.api.get('/api/v1/foc/schemes', query: {'partner_id': widget.client['id']}),
        Services.api.post('/api/v1/foc/preview', {
          'partner_id': widget.client['id'],
          'lines': [for (final l in widget.lines) {'product_id': l['id'], 'qty': l['qty']}],
        }),
      ]);
      if (!mounted) return;
      setState(() {
        _manualAllowed = (results[0] as Map)['manual_allowed'] == true;
        _free = ((results[1] as List?) ?? []).cast<Map<String, dynamic>>();
        _freeChecked = true;
      });
    } catch (_) {
      // Offline or no FOC module: the server works the free units out when the order arrives.
    }
  }

  Future<void> _addManual() async {
    final qty = TextEditingController(text: '1');
    final reason = TextEditingController();
    int? productId = widget.lines.isEmpty ? null : widget.lines.first['id'] as int;
    final added = await showDialog<bool>(
      context: context,
      builder: (dialog) => StatefulBuilder(
        builder: (context, setDialog) => AlertDialog(
          title: const Text('Add free goods (FOC)'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<int>(
                initialValue: productId,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Product'),
                items: [
                  for (final l in widget.lines)
                    DropdownMenuItem(value: l['id'] as int, child: Text('${l['name']}', overflow: TextOverflow.ellipsis)),
                ],
                onChanged: (v) => setDialog(() => productId = v),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: qty,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'Free quantity'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: reason,
                decoration: const InputDecoration(labelText: 'Reason *', hintText: 'Sample, display, damage cover…'),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialog, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(dialog, true), child: const Text('Add')),
          ],
        ),
      ),
    );
    final quantity = double.tryParse(qty.text.trim()) ?? 0;
    final why = reason.text.trim();
    WidgetsBinding.instance.addPostFrameCallback((_) => Future.delayed(const Duration(milliseconds: 400), () {
          qty.dispose();
          reason.dispose();
        }));
    if (added != true || productId == null) return;
    if (quantity <= 0 || why.isEmpty) {
      if (mounted) showSnack(context, 'Enter a quantity and the reason.');
      return;
    }
    final line = widget.lines.firstWhere((l) => l['id'] == productId);
    setState(() => _manual.add({'product_id': productId, 'name': line['name'], 'qty': quantity, 'reason': why}));
  }

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  double get _total => widget.lines
      .fold(0.0, (sum, l) => sum + ((l['price'] as num?) ?? 0) * ((l['qty'] as num?) ?? 0));

  Future<void> _submit() async {
    setState(() => _busy = true);
    try {
      Position? pos;
      try {
        pos = await currentPosition(recentOk: true);
      } catch (_) {
        // Orders are accepted without a fresh GPS fix.
      }
      final result = await Services.outbox.submit('/api/v1/orders', {
        'partner_id': widget.client['id'],
        'lines': [
          for (final l in widget.lines) {'product_id': l['id'], 'qty': l['qty']},
        ],
        if (_manual.isNotEmpty)
          'foc': [for (final m in _manual) {'product_id': m['product_id'], 'qty': m['qty'], 'reason': m['reason']}],
        'note': _note.text.trim(),
        if (_distributorId != null) 'distributor_id': _distributorId,
        'lat': pos?.latitude,
        'lng': pos?.longitude,
        'uuid': _uuid,
      }, label: '${demandFlow ? 'Demand' : 'Order'} · ${widget.client['name']}');
      final order = result.map;
      if (!mounted) return;
      if (result.queued) {
        await showDialog<void>(
          context: context,
          builder: (ctx) => AlertDialog(
            icon: const Icon(Icons.cloud_off_rounded, color: AppColors.warning, size: 48),
            title: Text('${demandFlow ? 'Demand' : 'Order'} saved offline'),
            content: const Text('It is kept on this phone and goes to the office as soon as you have network.'),
            actions: [FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK'))],
          ),
        );
        if (mounted) Navigator.of(context).pop(true);
        return;
      }
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          icon: const Icon(Icons.check_circle, color: Colors.green, size: 48),
          title: Text(demandFlow
              ? 'Demand ${order['name']} recorded'
              : 'Order ${order['name']} placed'),
          content: Text(demandFlow
              ? '${fmtMoney(order['amount_total'] as num?, order['currency'] as String?)} at PTR. '
                  'The office will send it to the distributor.'
              : 'Total ${fmtMoney(order['amount_total'] as num?, order['currency'] as String?)} incl. tax'),
          actions: [FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK'))],
        ),
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) showSnack(context, e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Who supplies the order: the field picks, the office sees it on the record.
  Widget _distributorCard() {
    final chosen = _distributors.where((d) => d['id'] == _distributorId).firstOrNull;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                      color: AppColors.purple.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(11)),
                  child: const Icon(Icons.local_shipping_rounded, size: 18, color: AppColors.purple),
                ),
                const SizedBox(width: 9),
                const Expanded(
                  child: Text('Supplied by', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              demandFlow
                  ? 'The office sends this demand to the distributor you choose.'
                  : 'The order is billed to the distributor; the shop stays on it as the outlet.',
              style: const TextStyle(fontSize: 12, color: AppColors.muted),
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<int>(
              initialValue: chosen == null ? null : _distributorId,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Distributor',
                prefixIcon: Icon(Icons.store_mall_directory_rounded, size: 19, color: AppColors.primary),
                filled: true,
                fillColor: Colors.white,
              ),
              items: [
                for (final distributor in _distributors)
                  DropdownMenuItem(
                    value: distributor['id'] as int,
                    child: Text(
                      [
                        '${distributor['name']}',
                        if (asText(distributor['city']) != null) '· ${distributor['city']}',
                      ].join(' '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
              onChanged: (value) => setState(() => _distributorId = value),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(demandFlow ? 'Review Demand' : 'Review Order')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.store),
            title: Text(widget.client['name'] as String, style: theme.textTheme.titleMedium),
          ),
          if (_distributors.isNotEmpty) _distributorCard(),
          const Divider(),
          for (final l in widget.lines)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(l['name'] as String),
              subtitle: Text('${fmtQty(l['qty'] as num)} × ${fmtMoney(l['price'] as num?)}'),
              trailing: Text(fmtMoney(((l['price'] as num?) ?? 0) * (l['qty'] as num))),
            ),
          if (_free.isNotEmpty || _manual.isNotEmpty || _manualAllowed || !_freeChecked) ...[
            const Divider(),
            Row(
              children: [
                const Icon(Icons.redeem_rounded, color: AppColors.success, size: 20),
                const SizedBox(width: 8),
                const Expanded(child: Text('Free goods (FOC)', style: TextStyle(fontWeight: FontWeight.w800))),
                if (_manualAllowed && widget.lines.isNotEmpty)
                  TextButton.icon(onPressed: _addManual, icon: const Icon(Icons.add_rounded), label: const Text('Add')),
              ],
            ),
            if (!_freeChecked)
              const Text('Free units from schemes are worked out when the order reaches the office.',
                  style: TextStyle(color: AppColors.muted, fontSize: 12.5)),
            for (final f in _free)
              ListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: Text('${(f['product'] as Map)['name']}'),
                subtitle: Text('${(f['scheme'] as Map)['name']} · ${(f['scheme'] as Map)['summary']}'),
                trailing: Text('+${fmtQty((f['qty'] as num?) ?? 0)} free',
                    style: const TextStyle(color: AppColors.success, fontWeight: FontWeight.w800)),
              ),
            for (final m in _manual)
              ListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: Text('${m['name']}'),
                subtitle: Text('${m['reason']}'),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('+${fmtQty(m['qty'] as num)} free',
                        style: const TextStyle(color: AppColors.success, fontWeight: FontWeight.w800)),
                    IconButton(
                      icon: const Icon(Icons.close_rounded, size: 18),
                      onPressed: () => setState(() => _manual.remove(m)),
                    ),
                  ],
                ),
              ),
            if (_freeChecked && _free.isEmpty && _manual.isEmpty)
              const Text('No scheme applies to this cart.', style: TextStyle(color: AppColors.muted, fontSize: 12.5)),
          ],
          const Divider(),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(demandFlow ? 'Value at PTR' : 'Estimated total'),
            trailing: Text(fmtMoney(_total), style: theme.textTheme.titleMedium),
          ),
          Text("Taxes and the client's price list are applied by the server.", style: theme.textTheme.bodySmall),
          const SizedBox(height: 16),
          TextField(
            controller: _note,
            maxLines: 2,
            decoration: const InputDecoration(labelText: 'Note for the office (optional)', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: _busy ? null : _submit,
            icon: _busy
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.send),
            label: Padding(
                padding: const EdgeInsets.all(12),
                child: Text(demandFlow ? 'Record demand' : 'Place order'),
            ),
          ),
        ],
      ),
    );
  }
}
